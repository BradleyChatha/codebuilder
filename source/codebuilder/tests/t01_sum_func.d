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

unittest
{
    import fluent.asserts;

    mixin(genFunction());

    sum(20,   80).should.equal(100);
    sum(200, -100).should.equal(100);
}