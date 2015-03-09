import nodeunit.TestCase;
import serialization.*;

class TestDeflatableNoVersionA implements Deflatable {}

@version(3) class TestDeflatableNoVersionB extends TestDeflatableNoVersionA {}

@version(2) class TestDeflatableMixedVersionC extends TestDeflatableNoVersionB {}

@version(1) class TestDeflatableVersionA implements Deflatable {}

class DeflatableTest {
  public function new() { }

  static function getVersionByReflection(cls:Class<Dynamic>) : Int {
    return Reflect.callMethod(cls, Reflect.field(cls, "___deflatable_version"), []);
  }

  @test static public function test_deflatableVersionForNoSpecifiedVersionIsZero(test:TestCase) : Void {
    test.strictEqual(TestDeflatableNoVersionA.___deflatable_version(), 0);
    test.strictEqual(getVersionByReflection(TestDeflatableNoVersionA), 0);
  }

  @test static public function test_deflatableVersionForSpecifiedVersionIgnoresBaseClass(test:TestCase) : Void {
    test.strictEqual(TestDeflatableNoVersionB.___deflatable_version(), 3);
    test.strictEqual(getVersionByReflection(TestDeflatableNoVersionB), 3);
  }

  @test static public function test_deflatableVersionForSpecifiedVersion(test:TestCase) : Void {
    test.strictEqual(TestDeflatableVersionA.___deflatable_version(), 1);
    test.strictEqual(getVersionByReflection(TestDeflatableVersionA), 1);
  }

  @test static public function test_deflatableVersionForMixedVersionIsSingleInteger(test:TestCase) : Void {
    test.strictEqual(TestDeflatableMixedVersionC.___deflatable_version(), 2);
    test.strictEqual(getVersionByReflection(TestDeflatableMixedVersionC), 2);
  }
}
