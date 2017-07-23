///
module codebuilder.builder;

version(unittest) import fluent.asserts;

public import std.typecons : Flag, Yes, No;

/// Passed to functions such as `CodeBuilder.put` to control automatic tabbing.
alias UseTabs = Flag!"tabs";

/// Passed to functions such as `CodeBuilder.put` to control automatic new lines.
alias UseNewLines = Flag!"newLines";

/// A delegate that can be passed to functions such as `addFuncDeclaration` to allow flexible
/// generation of code.
alias CodeFunc = void delegate(CodeBuilder);

/++
 + A glorified wrapper around an `Appender` which supports automatic tabbing and new lines.
 +
 + On it's own, `CodeBuilder` may already be more desirable than manually formatting, tabbing new lining, 
 + a code string manually.
 +
 + UFCS can also be used to create functions that can ease the generation of code, such as `addFuncCall`,
 + `addFuncDeclaration`, `addReturn`, etc.
 ++/
final class CodeBuilder
{
    import std.array : Appender;

    private
    {
        Appender!(dchar[]) _data;
        size_t             _tabs;
        static const dchar _tabChar = '\t';

        size_t  _disableTabCount;
        size_t  _disableLinesCount;
    }

    public
    {
        /++
         + Increases the tab count, meaning anytime `CodeBuilder.put` is used an extra tab will be written before
         + the data passed to it.
         +
         + Notes:
         +  If the tab count is the same value as `size_t.max` then this function does nothing.
         + ++/
        @safe @nogc
        void entab() nothrow pure
        {
            // Overflow protection
            if(this._tabs == size_t.max)
                return;

            this._tabs += 1;
        }

        /++
         + Decreases the tab count.
         +
         + Notes:
         +  If the tab count is 0 then this function does nothing.
         + ++/
        @safe @nogc
        void detab() nothrow pure
        {
            // Underflow protection
            if(this._tabs == 0)
                return;

            this._tabs -= 1;
        }

        /++
         + Disables automatic tabbing and/or new line insertion.
         +
         + Notes:
         +  For every call to `disable`, a call to `enable` is required to re-enable the functionality.
         +
         +  For example, if 2 calls to `disable` are made to disable tabbing, then 2 calls to `enable` for tabbing must be made
         +  before tabbing is re-enabled.
         +
         + Params:
         +  disableTabs  = If `Yes.tabs` then automatic tabbing will be disabled.
         +  disableLines = If `Yes.newLines` then automatic new line insertion will be disabled.
         +
         + See_Also:
         +  `CodeBuilder.enable`
         + ++/
        @safe @nogc
        void disable(UseTabs disableTabs = Yes.tabs, UseNewLines disableLines = Yes.newLines) nothrow pure
        {
            void _disable(ref size_t counter, bool doAction)
            {
                if(counter == size_t.max || !doAction)
                    return;

                counter += 1;
            }

            _disable(this._disableLinesCount, disableLines);
            _disable(this._disableTabCount,   disableTabs);
        }

        /++
         + Enables automatic tabbing and/or new line insertion.
         +
         + Params:
         +  enableTabs  = If `Yes.tabs` then automatic tabbing will be enabled.
         +  enableLines = If `Yes.newLines` then automatic new line insertion will be enabled.
         +
         + See_Also:
         +  `CodeBuilder.disable`
         + ++/
        @safe @nogc
        void enable(UseTabs enableTabs = Yes.tabs, UseNewLines enableLines = Yes.newLines) nothrow pure
        {
            void _enable(ref size_t counter, bool doAction)
            {
                if(counter == 0 || !doAction)
                    return;

                counter -= 1;
            }

            _enable(this._disableLinesCount, enableLines);
            _enable(this._disableTabCount,   enableTabs);
        }

        /++
         + Inserts data into the code string.
         +
         + Notes:
         +  `T` can be anything supported by `Appender!(dchar[])`
         +
         +  `CodeBuilder.enable` and `CodeBuilder.disable` are used to enable/disable the functionality of
         +  `doTabs` and `doLines` regardless of their values.
         +
         +   For ranges of `dchar[]` (such as `dchar[][]`) the functionality of `doTabs` and `doLines` will be applied to each
         +   `dchar[]` given.
         +
         + Params:
         +  data    = The data to insert.
         +  doTabs  = If `Yes.tabs` then a certain amount of tabs (see `CodeBuilder.entab`) will be inserted
         +            before `data` is inserted.
         +  doLines = If `Yes.newLines` then a new line will be inserted after `data`.
         + ++/
        void put(T)(T data, UseTabs doTabs = Yes.tabs, UseNewLines doLines = Yes.newLines)
        {
            import std.array;
            import std.algorithm : map;
            import std.range     : repeat, isInputRange, chain, ElementEncodingType, take;

            // For now, I'm just going to rely on the compiler's error message for when
            // the user passes something that Appender doesn't like.
            
            if(this._disableLinesCount > 0)
                doLines = No.newLines;
            
            if(this._disableTabCount > 0)
                doTabs = No.tabs;

            auto tabs = this._tabChar.repeat((doTabs) ? this._tabs : 0);
            auto line = ['\n'].take((doLines) ? 1 : 0);

            static if(isInputRange!T && is(ElementEncodingType!T : dchar[])) // ranges of dchar[]
            {
                // TODO: Actually bother to test this. `chain` wouldn't work in the else statement, so possibly won't work here.
                this._data.put(data.map!(str => chain(tabs, str, line)));
            }
            else // dstring/ranges of dchar
            {
                this._data.put(tabs);
                this._data.put(data);
                this._data.put(line);
            }
        }

        /// overload ~=
        void opOpAssign(string op : "~", T)(T data)
        {
            this.put(data);
        }

        /++
         + Returns:
         +  The code currently generated.
         + ++/
        @property @safe @nogc
        const(dchar)[] data() nothrow pure const
        {
            return this._data.data;
        }
    }
}

/// Describes a variable.
struct Variable
{
    /// The name of the variable's type.
    dstring typeName;

    /// The name of the variable.
    dstring name;

    /// The `CodeFunc` which generates the default value of the variable.
    CodeFunc defaultValue;
}

/++
 + A helper function that entabs the given `CodeBuilder`, calls a delegate to generate some code, and then detabs the `CodeBuilder`.
 +
 + Params:
 +  builder = The `CodeBuilder` to use.
 +  code    = The `CodeFunc` to use.
 +
 + Returns:
 +  `builder`
 + ++/
CodeBuilder putEntabbed(CodeBuilder builder, CodeFunc code)
{
    builder.entab();
    code(builder);
    builder.detab();

    return builder;
}
///
unittest
{
    auto builder = new CodeBuilder();

    builder.put("Hello");
    builder.data.should.equal("Hello\n");

    builder.putEntabbed(b => b.put("World"));
    builder.data.should.equal("Hello\n\tWorld\n");
}

/++
 + A helper function to write the given code in between two '"'s
 +
 + Notes:
 +  `T` can be any type that can be passed to `CodeBuilder.put`.
 +
 + Params:
 +  builder = The `CodeBuilder` to use.
 +  str     = The code to write.
 +
 + Returns:
 +  `builder`
 + ++/
CodeBuilder putString(T)(CodeBuilder builder, T str)
{
    builder.disable();

    builder.put('"');
    builder.put(str);
    builder.put('"');

    builder.enable();
    return builder;
}
///
unittest
{
    auto builder = new CodeBuilder();

    builder.put("Hello");
    builder.putString("World!");

    builder.data.should.equal("Hello\n\"World!\"");
}

/++
 +
 + ++/
CodeBuilder putScope(CodeBuilder builder, CodeFunc func)
{
    builder.put('{');
    builder.putEntabbed(b => func(b));
    builder.put('}');

    return builder;
}
///
unittest
{
    auto builder = new CodeBuilder();
    builder.putScope(
        (b)
        {
            b.addFuncCall("writeln", "\"Hello world!\"");
        });

    builder.data.should.equal("{\n\twriteln(\"Hello world!\");\n}\n");
}

/++
 + Formatted version of `CodeBuilder.put`.
 +
 + Params:
 +  builder   = The `CodeBuilder` to use.
 +  formatStr = The format string to pass to `std.format.format`
 +  params    = The paramters to pass to `std.format.format`
 +
 + Returns:
 +  `builder`
 + ++/
CodeBuilder putf(Params...)(CodeBuilder builder, dstring formatStr, Params params)
{
    import std.format : format;

    builder.put(format(formatStr, params));

    return builder;
}
///
unittest
{
    auto builder = new CodeBuilder();
    builder.putf("if(%s == %s)", "\"Hello\"", "\"World\"");

    builder.data.should.equal("if(\"Hello\" == \"World\")\n");
}

/++
 + A helper function which accepts a wide variety of parameters to pass to `CodeBuilder.put`.
 +
 + Supported_Types:
 +  InputRanges of characters (dstring, for example) - Written in as-is, with no modification.
 +
 +  `CodeFunc` - The `CodeFunc` is called with `builder` as it's parameter.
 +
 +  `Variable` - The name of the variable is written.
 +
 +  Any built-in D type - The result of passing the parameter to `std.conv.to!string` is written.
 +
 + Params:
 +  builder = The `CodeBuilder` to use.
 +  param   = The parameter to put.
 +
 + Returns:
 +  `builder`
 + ++/
CodeBuilder putExtended(T)(CodeBuilder builder, T param)
{
    import std.range  : isInputRange;
    import std.conv   : to;
    import std.traits : isBuiltinType, isSomeFunction;

    alias PType = T;

    static if(is(PType : dstring) || isInputRange!PType)
        builder.put(param);
    else static if(is(PType : CodeFunc))
        param(builder);
    else static if(is(PType == Variable))
        builder.put(param.name);
    else static if(isBuiltinType!PType)
        builder.put(param.to!dstring);
    else static if(isSomeFunction!PType) // CodeFunc desctibes a delegate, so for functions we need to turn them into delegates first.
    {
        import std.functional : toDelegate;

        auto del = param.toDelegate;
        static assert(is(typeof(del) : CodeFunc), "Function of type '" ~ PType.stringof ~ "' is not convertable to a CodeFunc");

        builder.putExtended(del);
    }
    else
        static assert(false, "Unsupported type: " ~ PType.stringof);

    return builder;
}
///
unittest
{
    auto builder = new CodeBuilder();

    builder.putExtended("Hello"d)                           // strings
           .putExtended((CodeBuilder b) => b.put("World!")) // CodeFuncs
           .putExtended(Variable("int", "myVar", null))     // Variables (only their names are written)
           .putExtended(true);                              // Built-in D types (bools, ints, floats, etc.)

    builder.data.should.equal("Hello\nWorld!\nmyVar\ntrue\n"d);
}

/++
 + Creates a function using the given data.
 +
 + Params:
 +  builder     = The `CodeBuilder` to use.
 +  returnType  = The name of the type that the function returns.
 +  name        = The name of the function.
 +  params      = The function's parameters.
 +  body_       = The `CodeFunc` which generates the code for the function's body.
 +
 + Returns:
 +  `builder`
 + ++/
CodeBuilder addFuncDeclaration(CodeBuilder builder, dstring returnType, dstring name, Variable[] params, CodeFunc body_)
{
    import std.algorithm : map, joiner;

    builder.put(returnType ~ " " ~ name, Yes.tabs, No.newLines);

    builder.disable();
    builder.put("(");        
    builder.put(params.map!(v => v.typeName ~ " " ~ v.name)
                        .joiner(", "));
    builder.enable();
    builder.put(")", No.tabs);

    builder.putScope(body_);
    return builder;
}
///
unittest
{
    auto builder = new CodeBuilder();

    builder.addFuncDeclaration("int", "sum", [Variable("int", "a"), Variable("int", "b")], (b){b.addReturn("a + b"d);});

    builder.data.should.equal("int sum(int a, int b)\n{\n\treturn a + b;\n}\n");
}

/++
 + Creates a function using the given data.
 +
 + Params:
 +  returnType  = The type that the function return.
 +
 +  builder     = The `CodeBuilder` to use.
 +  name        = The name of the function.
 +  params      = The function's parameters.
 +  body_       = The `CodeFunc` which generates the code for the function's body.
 +
 + Returns:
 +  `builder`
 + ++/
CodeBuilder addFuncDeclaration(returnType)(CodeBuilder builder, dstring name, Variable[] params, CodeFunc body_)
{
    import std.traits : fullyQualifiedName;

    return builder.addFuncDeclaration(fullyQualifiedName!returnType, name, params, body_);
}
///
unittest
{
    auto builder = new CodeBuilder();

    builder.addFuncDeclaration!int("six", null, (b){b.addReturn("6"d);});

    builder.data.should.equal("int six()\n{\n\treturn 6;\n}\n");
}

/++
 + Creates an import statement.
 +
 + Notes:
 +  If `selection` is `null`, then the entire module is imported.
 +  Otherwise, only the specified symbols are imported.
 +
 + Params:
 +  builder = The `CodeBuilder` to use.
 +  moduleName = The name of the module to import.
 +  selection = An array of which symbols to import from the module.
 +
 + Returns:
 +  `builder`
 + ++/
CodeBuilder addImport(CodeBuilder builder, dstring moduleName, dstring[] selection = null)
{
    builder.put("import " ~ moduleName, Yes.tabs, No.newLines);
    
    if(selection !is null)
    {
        import std.algorithm : joiner;
        builder.disable(); // Disables both (tabbing and new lines) by default.

        builder.put(" : ");
        builder.put(selection.joiner(", "d));

        builder.enable(); // Likewise, enables both by default
    }

    builder.put(';', No.tabs);
    return builder;
}
///
unittest
{
    auto builder = new CodeBuilder();

    // Import entire module
    builder.addImport("std.stdio");
    builder.data.should.equal("import std.stdio;\n");

    builder = new CodeBuilder(); // Just to keep the asserts clean to read.


    // Selective imports
    builder.addImport("std.stdio", ["readln"d, "writeln"d]);
    builder.data.should.equal("import std.stdio : readln, writeln;\n");
}

/++
 + Declares a variable, and returns a `Variable` which can be used to easily reference the variable.
 +
 + Notes:
 +  `valueFunc` may be `null`.
 +
 + Params:
 +  builder   = The `CodeBuilder` to use.
 +  type      = The name of the variable's type.
 +  name      = The name of the variable.
 +  valueFunc = The `CodeFunc` which generates the code to set the variable's intial value.
 +
 + Returns:
 +  A `Variable` describing the variable declared by this function.
 + ++/
Variable addVariable(CodeBuilder builder, dstring type, dstring name, CodeFunc valueFunc = null)
{
    builder.put(type ~ " " ~ name, Yes.tabs, No.newLines);

    if(valueFunc !is null)
    {
        builder.disable(); // Disable automatic tabs and new lines.

        builder.put(" = ");
        valueFunc(builder);

        builder.enable(); // Enable them both
    }

    builder.put(";", No.tabs);
    return Variable(type, name, valueFunc);
}
///
unittest
{
    auto builder = new CodeBuilder();

    // Declare the variable without setting it.
    auto six = builder.addVariable("int", "six");
    builder.data.should.equal("int six;\n"d);
    six.should.equal(Variable("int", "six"));

    builder = new CodeBuilder();


    // Declare the variable, and set it's value.
    CodeFunc func = (b){b.put("6");};
             six  = builder.addVariable("int", "six", func);

    builder.data.should.equal("int six = 6;\n");
    six.should.equal(Variable("int", "six", func));
}

/// A helper function to more easily specify the variable's type.
Variable addVariable(T)(CodeBuilder builder, dstring name, CodeFunc valueFunc = null)
{
    import std.traits : fullyQualifiedName;

    return builder.addVariable(fullyQualifiedName!T, name, valueFunc);
}
///
unittest
{
    auto builder = new CodeBuilder();

    builder.addVariable!int("six", (b){b.put("6");});
    builder.data.should.equal("int six = 6;\n");
}

/// A helper function for `addVariable` which creates an alias.
Variable addAlias(CodeBuilder builder, dstring name, CodeFunc valueFunc)
{
    return builder.addVariable("alias", name, valueFunc);
}
///
unittest
{
    auto builder = new CodeBuilder();
    builder.addAlias("SomeType", (b){b.put("int");});
    builder.data.should.equal("alias SomeType = int;\n");
}

/// A helper function for `addVariable` which creates an enum value.
Variable addEnumValue(CodeBuilder builder, dstring name, CodeFunc valueFunc)
{
    return builder.addVariable("enum", name, valueFunc);
}
///
unittest
{
    auto builder = new CodeBuilder();
    builder.addEnumValue("SomeValue", (b){b.put("6");});
    builder.data.should.equal("enum SomeValue = 6;\n");
}

/++
 + Creates a return statement.
 +
 + Notes:
 +  `T` can be any type supported by `putExtended`.
 +
 + Params:
 +  builder = The `CodeBuilder` to use.
 +  code    = The code to use in the return statement.
 +
 + Returns:
 +  `builder`
 + ++/
CodeBuilder addReturn(T)(CodeBuilder builder, T code)
{
    builder.put("return ", Yes.tabs, No.newLines);
    builder.disable();

    builder.putExtended(code);

    builder.enable();
    builder.put(";", No.tabs, Yes.newLines);

    return builder;
}
///
unittest
{
    auto builder = new CodeBuilder();

    // Option #1: Pass in a dstring, and it'll be added as-is.
    builder.addReturn("21 * 8"d);
    builder.data.should.equal("return 21 * 8;\n");

    builder = new CodeBuilder();


    // Option #2: Pass in an instance of Variable, and the variable's name is added.
    builder.addReturn(Variable("int", "someNumber"));
    builder.data.should.equal("return someNumber;\n");

    builder = new CodeBuilder();


    // Option #3: Pass in a CodeFunc, and let it deal with generating the code it needs.
    CodeFunc func = (b){b.put("200 / someNumber");};
    builder.addReturn(func);
    builder.data.should.equal("return 200 / someNumber;\n");
}

/++
 + Creates a call to a function.
 +
 + Notes:
 +  `params` can be made up of any combination of values supported by `putExtended`.
 +
 +  Strings $(B won't) be automatically enclosed between speech marks('"').
 +
 + Params:
 +  semicolon = If `Yes.semicolon`, then a ';' is inserted at the end of the function call.
 +
 +  builder  = The `CodeBuilder` to use.
 +  funcName = The name of the function to call.
 +  params   = The parameters to pass to the function.
 +
 + Returns:
 +  `builder`
 + ++/
CodeBuilder addFuncCall(Flag!"semicolon" semicolon = Yes.semicolon, Params...)(CodeBuilder builder, dstring funcName, Params params)
{
    import std.conv   : to;
    import std.range  : isInputRange;
    import std.traits : isBuiltinType;

    builder.put(funcName, Yes.tabs, No.newLines);
    builder.disable();
    builder.put('(');

    foreach(i, param; params)
    {
        builder.putExtended(param);

        static if(i != params.length - 1)
            builder.put(", ");
    }

    builder.enable();
    builder.put(')', No.tabs, No.newLines);

    static if(semicolon)
        builder.put(';', No.tabs);

    return builder;
}
///
unittest
{
    auto builder = new CodeBuilder();

    // DStrings(Including input ranges of them), CodeFuncs, built-in types(int, bool, float, etc.), and Variables can all be passed as parameters.
    dstring  str  = "\"Hello\""d;
    CodeFunc func = (b){b.putString("World!");};
    Variable vari = Variable("int", "someVar");

    builder.addFuncCall("writeln", str, func, vari);

    builder.data.should.equal("writeln(\"Hello\", \"World!\", someVar);\n");
}