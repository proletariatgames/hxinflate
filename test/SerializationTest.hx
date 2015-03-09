import nodeunit.TestCase;
import serialization.*;

class TestClassA implements Deflatable {
  public var testBoolA : Bool = true;
  public var testFloatA : Float = 1.7;
  public var testIntA : Float = 3;
  public var testStringA : String = "testStringA";

  public function new() : Void {}
}

/*
// CLASS_B_VERSION_0
class TestClassB {
  public var testBoolB : Bool = true;
  public var testFloatB : Float = 1.7;
  public var testIntB : Float = 3;
  public var testStringB : String = "testStringB";
  public function new() : Void {}
}
*/
@version(1)
class TestClassB implements Deflatable {
  public var testFloatB : String;
  public var testIntB : Float;
  public var testStringB : String;
  public function new() : Void {}

  public static function _upgrade_version(instance:Dynamic, version:Int, fieldsMap:Map<String, Dynamic>) {
    var oldFloatB = fieldsMap["testFloatB"];
    fieldsMap.set("testFloatB", '${oldFloatB * 2}');
    fieldsMap.remove("testBoolB");
  }
}

/*
// CLASS_C_VERSION_0
class TestClassC implements Deflatable {
  public function new() : Void {}

  @:keep
  function hxSerialize( s : Deflater ) {
    s.serialize("blah");
    s.serialize(-1.3);
  }

  @:keep
  function hxUnserialize( s : Inflater, instanceClassIndex : Int ) {
    s.unserialize();
    s.unserialize();
  }
}
*/
@version(1)
class TestClassC implements Deflatable {
  public var testStringC(default, null) : String;
  public function new() : Void {}

  @:keep
  function hxSerialize( s : Deflater ) {
    s.serialize(testStringC);
  }

  @:keep
  function hxUnserialize( s : Inflater, instanceClassIndex : Int ) {
    if (s.getClassVersion(TestClassC, instanceClassIndex) < 1) {
      s.unserialize();
      testStringC = '${s.unserialize()}';
    } else {
      testStringC = s.unserialize();
    }
  }
}

/*
// CLASS_D_VERSION_0
class TestClassD {
  public var testFloatD : Float = 3.6;
  public var testIntD : Float = 3;
  public var testStringD : String = "testStringD";

  public function new() : Void {}
}
*/
@version(1)
class TestClassD implements Deflatable {
  public var testIntD : Int;
  public function new() : Void {}

  public static function _upgrade_version(instance:Dynamic, version:Int, fieldsMap:Map<String, Dynamic>) {
    var oldIntD:Float = fieldsMap["testIntD"];
    fieldsMap.set("testIntD", Math.floor(oldIntD * 2.5));
    fieldsMap.remove("testFloatD");
    fieldsMap.remove("testStringD");
  }
}
class TestClassDSub extends TestClassD {
  public var testMap : Map<String, Float>;

  public function new() : Void {
    super();
    testMap = new Map();
    testMap.set("blah", 1.6);
  }
}

/*
// CLASS_E_VERSION_0
class TestClassE extends TestClassEBase1{
  public var testFloatE : Float = 3.6;

  public function new() : Void { super(); }
}
*/
@version(1)
class TestClassE extends TestClassEBase2{
  public var testFloatE : Float = 2;

  public function new() : Void { super(); }

  public static function _upgrade_version(instance:Dynamic, version:Int, fieldsMap:Map<String, Dynamic>) {
    var testStringE = fieldsMap["testStringE"];
    fieldsMap.remove("testStringE");
    fieldsMap.set("newTestStringE", testStringE);
  }
}
class TestClassEBase1 {
  public var testStringE : String = "test";

  public function new() : Void {}
}
class TestClassEBase2 implements Deflatable {
  public var newTestStringE : String = null;

  public function new() : Void {}
}

/*
// CLASS_F_VERSION_0
class TestClassF {
  public var testVar : String = "test";

  public function new() : Void {}
}
// CLASS_F_VERSION_1
@version(1)
class TestClassF implements Deflatable {
  public var testVar : Array<String>;

  public function new() : Void {
    testVar = [];
    testVar.push("test2");
  }
}
*/
@version(2)
class TestClassF implements Deflatable {
  public var testVar : Map<String, Int>;

  public function new() : Void {
    testVar = new Map();
  }

  public static function _upgrade_version(instance:Dynamic, version:Int, fieldsMap:Map<String, Dynamic>) {
    if (version == 0) {
      var oldString = fieldsMap["testVar"];
      var newMap:Map<String, Int> = new Map();
      newMap.set(oldString, 100);
      fieldsMap.set("testVar", newMap);
    } else if (version == 1) {
      var oldArray:Array<String> = fieldsMap["testVar"];
      var newMap:Map<String, Int> = new Map();
      for (elem in oldArray) {
        newMap.set(elem, 50);
      }
      fieldsMap.set("testVar", newMap);
    }
  }
}

/*
// CLASS_G_VERSION_0
class TestClassG extends TestClassGBase {
  public var testString : String = "test";

  public function new() : Void { super(); }
}
// CLASS_G_BASE_VERSION_0
class TestClassGBase {
  public var testBool : Bool = false;

  public function new() : Void {}
}
*/
@version(1)
class TestClassG extends TestClassGBase {
  public var testString : Array<String>;

  public function new() : Void {
    testString = ["something", "other"];
    super();
  }

  public static function _upgrade_version(instance:Dynamic, version:Int, fieldsMap:Map<String, Dynamic>) {
    if (version < 1) {
      var oldString:String = fieldsMap["testString"];
      fieldsMap.set("testString", [oldString]);
    }
  }
}
@version(1)
class TestClassGBase implements Deflatable {
  public var testBool : Map<String, Bool>;

  public function new() : Void {
    testBool = new Map();
    testBool.set("first", true);
  }

  public static function _upgrade_version(instance:Dynamic, version:Int, fieldsMap:Map<String, Dynamic>) {
    if (version < 1) {
      var oldBool:Bool = fieldsMap["testBool"];
      var newMap:Map<String, Bool> = new Map();
      newMap.set("first", oldBool);
      fieldsMap.set("testBool", newMap);
    }
  }
}

/*
class TestRemovedClass {
  public var fieldA:String;
  public var fieldB:Map<String, Bool>;
  public function new() {
    fieldA = "fieldA value";
    fieldB = ["first"=>true];
  }
}
*/

@version(1)
class TestRemovedClassTest implements Deflatable {
  // public var removedType : TestRemovedClass;
  public function new() {
    // this.removedType = new TestRemovedClass();
  }

  public static function _upgrade_version(instance:Dynamic, version:Int, fieldsMap:Map<String, Dynamic>) {
    if (version < 1) {
      fieldsMap.remove('removedType');
    }
  }
}

class SerializationTest {

  static function traceBlob(v : Dynamic) : Void {
    trace(Deflater.run(v));
  }

  @test static public function test_deserializeClassSameVersion(test:TestCase) : Void {
    var classA = new TestClassA();
    classA.testIntA = 4;
    var deflatedA = Deflater.run(classA);
    var inflatedA = Inflater.run(deflatedA);
    test.ok(inflatedA.testBoolA);
    test.strictEqual(1.7, inflatedA.testFloatA);
    test.strictEqual(4, inflatedA.testIntA);
    test.strictEqual("testStringA", inflatedA.testStringA);
  }

  public static var CLASS_B_VERSION_0 = "ZVER1VY10:TestClassB:i-1:z:f:4:Y11:testStringBY8:testIntBY10:testFloatBY9:testBoolB:R1i3d1.7tg";
  @test static public function test_upgradeChangeType(test:TestCase) : Void {
    var upgradedClassB = Inflater.run(CLASS_B_VERSION_0);
    test.strictEqual("3.4", upgradedClassB.testFloatB);
    test.strictEqual(3, upgradedClassB.testIntB);
    test.strictEqual("testStringB", upgradedClassB.testStringB);
  }

  public static var CLASS_C_VERSION_0 = "ZVER1VY10:TestClassC:i-1:z:t:Y4:blahd-1.3g";
  @test static public function test_upgradeCustomSerialization(test:TestCase) : Void {
    var upgradedClassC = Inflater.run(CLASS_C_VERSION_0);
    test.strictEqual("-1.3", upgradedClassC.testStringC);
    var deflatedClassC = Deflater.run(upgradedClassC);
    var inflatedClassC = Inflater.run(deflatedClassC);
    test.strictEqual("-1.3", upgradedClassC.testStringC);
  }

  public static var CLASS_D_SUB_VERSION_0_0 = "ZVER1WY10:TestClassD:i-1:z:f:3:Y11:testStringDY8:testIntDY10:testFloatD:VY13:TestClassDSub:z:z:f:4:Y7:testMapR1R2R3:bY4:blahd1.6hR1i3d3.6g";
  @test static public function test_upgradeBaseClass(test:TestCase) : Void {
    var upgradedClassDSub = Inflater.run(CLASS_D_SUB_VERSION_0_0);
    test.strictEqual(7, upgradedClassDSub.testIntD);
    test.strictEqual(1.6, upgradedClassDSub.testMap.get("blah"));
  }

  public static var CLASS_E_VERSION_0 = "ZVER1WY15:TestClassEBase1:i-1:z:f:1:Y11:testStringE:VY10:TestClassE:z:z:f:2:Y10:testFloatER1:d3.6Y4:testg";
  @test static public function test_upgradeSwitchBaseClass(test:TestCase) : Void {
    var upgradedClassE = Inflater.run(CLASS_E_VERSION_0);
    test.strictEqual(3.6, upgradedClassE.testFloatE);
    test.strictEqual("test", upgradedClassE.newTestStringE);
    test.ok(!Reflect.hasField(upgradedClassE, "testStringE"));
  }

  public static var CLASS_F_VERSION_0 = "ZVER1VY10:TestClassF:i-1:z:f:1:Y7:testVar:Y4:testg";
  @test static public function test_upgradeFromTwoVersionsAgo(test:TestCase) : Void {
    var upgradedClassF = Inflater.run(CLASS_F_VERSION_0);
    test.strictEqual(100, upgradedClassF.testVar.get("test"));
  }

  public static var CLASS_F_VERSION_1 = "ZVER1VY10:TestClassF:i-1:i1:f:1:Y7:testVar:aY5:test2hg";
  @test static public function test_upgradeFromOneVersionsAgo(test:TestCase) : Void {
    var upgradedClassF = Inflater.run(CLASS_F_VERSION_1);
    test.strictEqual(50, upgradedClassF.testVar.get("test2"));
  }

  public static var CLASS_G_VERSION_0_0 = "ZVER1WY14:TestClassGBase:i-1:z:f:1:Y8:testBool:VY10:TestClassG:z:z:f:2:Y10:testStringR1:Y4:testfg";
  @test static public function test_upgradeBothSuperClassAndBaseClassAtSameTime(test:TestCase) : Void {
    var upgradedClassG:TestClassG = Inflater.run(CLASS_G_VERSION_0_0);
    test.strictEqual(1, upgradedClassG.testString.length);
    test.strictEqual("test", upgradedClassG.testString[0]);
    test.strictEqual(false, upgradedClassG.testBool.get("first"));
  }

  public static var CLASS_G_VERSION_1_0 = "ZVER1WY14:TestClassGBase:i-1:z:f:1:Y8:testBool:VY10:TestClassG:z:i1:f:2:Y10:testStringR1:aY9:somethingY5:otherhfg";
  @test static public function test_upgradeBaseClassWithSuperAlreadyUpgraded(test:TestCase) : Void {
    var upgradedClassG:TestClassG = Inflater.run(CLASS_G_VERSION_1_0);
    test.strictEqual(2, upgradedClassG.testString.length);
    test.strictEqual("something", upgradedClassG.testString[0]);
    test.strictEqual(false, upgradedClassG.testBool.get("first"));
  }

  public static var CLASS_R_VERSION_0_0 = "ZVER3nVY20:TestRemovedClassTest:i-1:z:f:1:Y11:removedType:VY16:TestRemovedClass:i-1:z:f:2:Y6:fieldAY6:fieldB:Y12:fieldA valuebY5:firstthgg";
  @test static public function test_removedType(test:TestCase) : Void {
    RemovedTypes.add('TestRemovedClass');
    var upgradeClassR:TestRemovedClassTest = Inflater.run(CLASS_R_VERSION_0_0);
    test.strictEqual(Std.is(upgradeClassR, TestRemovedClassTest), true);
  }
}
