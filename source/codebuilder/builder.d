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
            import std.range     : repeat, isInputRange, chain, ElementEncodingType;

            // For now, I'm just going to rely on the compiler's error message for when
            // the user passes something that Appender doesn't like.
            
            if(this._disableLinesCount > 0)
                doLines = No.newLines;
            
            if(this._disableTabCount > 0)
                doTabs = No.tabs;

            auto tabs = this._tabChar.repeat(this._tabs);

            static if(isInputRange!T && is(ElementEncodingType!T : dchar[])) // ranges of dchar[]
            {
                if(doTabs)
                {
                    dchar[] newLine;
                    if(doLines)
                        newLine = ['\n'];

                    this._data.put(data.map!(str => chain(tabs, str, newLine)));
                }
                else
                {
                    this._data.put(data);

                    if(doLines)
                        this._data.put('\n');
                }
            }
            else // dstring/ranges of dchar
            {
                if(doTabs)
                    this._data.put(tabs);

                this._data.put(data);

                if(doLines)
                    this._data.put('\n');
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

///
struct Variable
{
    ///
    dstring typeName;

    ///
    dstring name;

    ///
    CodeFunc defaultValue;
}

///
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

///
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

///
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

    builder.put('{');
    builder.putEntabbed(b => body_(b));
    builder.put('}');
    return builder;
}
///
unittest
{
    auto builder = new CodeBuilder();

    builder.addFuncDeclaration("int", "sum", [Variable("int", "a"), Variable("int", "b")], (b){b.addReturn("a + b"d);});

    builder.data.should.equal("int sum(int a, int b)\n{\n\treturn a + b;\n}\n");
}

///
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

///
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

///
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

///
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

///
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

///
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

///
CodeBuilder addReturn(T)(CodeBuilder builder, T code)
{
    dstring returnCode;

    static if(is(T : dstring))
    {
        enum UseReturnCode = true;

        returnCode = code;
    }
    else static if(is(T == Variable))
    {
        enum UseReturnCode = true;

        returnCode = code.name;
    }
    else static if(is(T : CodeFunc))
    {
        enum UseReturnCode = false;

        builder.put("return ", Yes.tabs, No.newLines);
        
        builder.disable();
        code(builder);
        builder.enable();

        builder.put(";", No.tabs);
    }
    else
        static assert(false, T.stringof);

    static if(UseReturnCode)
        builder.put("return " ~ returnCode ~ ";");

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

///
CodeBuilder addFuncCall(Flag!"semicolon" semicolon = Yes.semicolon, Params...)(CodeBuilder builder, dstring funcName, Params params)
{
    import std.conv   : to;
    import std.range  : isInputRange;
    import std.traits : isBuiltinType;

    builder.put(funcName, No.tabs, No.newLines);
    builder.disable();
    builder.put('(');

    foreach(i, param; params)
    {
        alias PType = typeof(param);

        static if(is(PType : dstring) || isInputRange!PType)
            builder.put(param);
        else static if(is(PType : CodeFunc))
            param(builder);
        else static if(is(PType == Variable))
            builder.put(param.name);
        else static if(isBuiltinType!PType)
            builder.put(param.to!string);
        else
            static assert(false, "Unknown type: " ~ PType.stringof);

        static if(i != params.length - 1)
            builder.put(", ");
    }

    builder.enable();
    builder.put(')', No.tabs, No.newLines);

    if(semicolon)
        builder.put(';', No.tabs);

    return builder;
}
///
unittest
{
    auto builder = new CodeBuilder();

    // DStrings(Including input ranges of them), CodeFuncs, built-in types(int, bool, float, etc.), and Variables can all be passed as parameters.
    // The 'putString' function can be used to perform this as well
    dstring  str  = "\"Hello\""d;
    CodeFunc func = (b){b.putString("World!");};
    Variable vari = Variable("int", "someVar");

    builder.addFuncCall("writeln", str, func, vari);

    builder.data.should.equal("writeln(\"Hello\", \"World!\", someVar);\n");
}