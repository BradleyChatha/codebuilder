module codebuilder.tests.t1;

import codebuilder;

dstring genFunction()
{
    auto builder = new CodeBuilder();

    builder.addFuncDeclaration!int(
        "sum", [Variable("int", "a"), Variable("int", "b")],
        (b)
        {
            b.addReturn("a + b"d);            
        }
    );

    return builder.data.idup;
}

dstring genTest(int a, int b, int expected)
{
    auto builder = new CodeBuilder();

    builder.addFuncCall("Assert.equal", 
                        (CodeBuilder build)
                            {build.addFuncCall!(No.semicolon)("sum", a, b);}, 
                        expected);

    return builder.data.idup;
}

unittest
{
    import fluent.asserts;

    mixin(genFunction());

    sum(20, 80).should.equal(100);
    sum(200, -100).should.equal(100);

    mixin(genTest(50, 25, 75));
    mixin(genTest(1, 1, 2));
}