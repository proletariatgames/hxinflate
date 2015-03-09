
class TestMain extends nodeunit.TestMain {
  static function main() {
    var main = new TestMain();

    main.installSourceMap();

    main.initMain(TestMain);
    main.addSuite(TestSuite);
  }
}
