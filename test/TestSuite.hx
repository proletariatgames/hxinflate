
class TestSuite extends nodeunit.TestSuite {
  public function new() {
    super();
    add(DeflatableTest);
    add(SerializationTest);
  }
}
