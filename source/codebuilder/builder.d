///
module codebuilder.builder;

version(unittest) import fluent.asserts;

public import std.typecons : Flag, Yes, No;

///
alias UseTabs = Flag!"tabs";

///
alias UseNewLines = Flag!"newLines";

///
alias CodeFunc = void delegate(CodeBuilder);

///
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
        ///
        @safe @nogc
        void entab() nothrow pure
        {
            // Overflow protection
            if(this._tabs == size_t.max)
                return;

            this._tabs += 1;
        }

        ///
        @safe @nogc
        void detab() nothrow pure
        {
            // Underflow protection
            if(this._tabs == 0)
                return;

            this._tabs -= 1;
        }

        ///
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

        ///
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

        ///
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

            static if(isInputRange!T && is(ElementEncodingType!T : dchar[]))
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
            else
            {
                if(doTabs)
                    this._data.put(tabs);

                this._data.put(data);

                if(doLines)
                    this._data.put('\n');
            }
        }

        ///
        void opOpAssign(string op : "~", T)(T data)
        {
            this.put(data);
        }

        ///
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
    else static if(is(T == CodeFunc))
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
CodeBuilder addFuncCall(Params...)(CodeBuilder builder, dstring funcName, Params params)
{
    import std.range : isInputRange;

    builder.put(funcName, No.tabs, No.newLines);
    builder.disable();
    builder.put('(');

    foreach(i, param; params)
    {
        alias PType = typeof(param);

        static if(is(PType : dstring) || isInputRange!PType)
            builder.putString(param);
        else static if(is(PType == CodeFunc))
            param(builder);
        else static if(is(PType == Variable))
            builder.put(param.name);
        else
            static assert(false, "Unknown type: " ~ PType.stringof);

        static if(i != params.length - 1)
            builder.put(", ");
    }

    builder.enable();
    builder.put(')', No.tabs, No.newLines);
    builder.put(';', No.tabs);
    return builder;
}
///
unittest
{
    auto builder = new CodeBuilder();

    // DStrings(Including input ranges of them), CodeFuncs, and Variables can all be passed as parameters.
    // Strings are automatically enclosed in speech marks.
    // The 'putString' function can be used to perform this as well
    dstring  str  = "Hello"d;
    CodeFunc func = (b){b.putString("World!");};
    Variable vari = Variable("int", "someVar");

    builder.addFuncCall("writeln", str, func, vari);

    builder.data.should.equal("writeln(\"Hello\", \"World!\", someVar);\n");
}