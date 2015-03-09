//------------------------------------------------------------------------------
// Copyright 2015 Proletariat Inc. All rights reserved.
// Owner : Dan Brakeley
//------------------------------------------------------------------------------
import serialization.internal.TypeUtils;
import nodeunit.TestCase;

private enum TestEnum {
  First;
  Second;
  Third;
}

class TypeUtilsTest
{
  static function isEnumEq(test:TestCase, actual:EnumValue, expected:EnumValue) : Void {
    test.ok(Type.enumEq(actual, expected), 'Expected $expected but was $actual');
  }

  @test static public function test_parseEnum_valid_value(test:TestCase) : Void {
    var e : TestEnum = TypeUtils.parseEnum(TestEnum, "First", Second);
    isEnumEq(test, e, First);
    e = TypeUtils.parseEnum(TestEnum, "Second", Third);
    isEnumEq(test, e, Second);
    e = TypeUtils.parseEnum(TestEnum, "Third", First);
    isEnumEq(test, e, Third);
  }

  @test static public function test_parseEnum_invalid_value_uses_default(test:TestCase) : Void {
    var e : TestEnum = TypeUtils.parseEnum(TestEnum, "NotReal", First);
    isEnumEq(test, e, First);
    e = TypeUtils.parseEnum(TestEnum, "AlsoFake", Second);
    isEnumEq(test, e, Second);
    e = TypeUtils.parseEnum(TestEnum, "", Third);
    isEnumEq(test, e, Third);
  }

  @test static public function test_parseEnum_null_value_uses_default(test:TestCase) : Void {
    for (value in Type.allEnums(TestEnum)) {
      var e = TypeUtils.parseEnum(TestEnum, null, value);
      isEnumEq(test, e, value);
    }
  }
}

