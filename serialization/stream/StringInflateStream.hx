package serialization.stream;

/** Stream implementation based on a string input */
class StringInflateStream implements IInflateStream
{
  var buf:String;
  var pos:Int;
  var offset:Int;
  var length:Int;

  public function new(buf:String, offset:Int=0, length:Int=-1) : Void {
    this.buf = buf;
    this.length = length < 0 ? buf.length : length;
    this.offset = offset;
    this.pos = offset;
  }

  public function dispose() this.buf = null;
  public function getPos() return pos-offset;
  public function seekTo(pos:Int) this.pos = pos+offset;
  public function peekByte() return Inflater.fastCodeAt(buf, pos);
  public function readByte() return Inflater.fastCodeAt(buf, pos++);
  public function getLength() return length;
  public function eof() return pos-offset >= length;
  public function toString() return this.buf;

  public function readString(len:Int) : String {
    var s = buf.substr(pos, len);
    pos += len;
    return s;
  }

  public function sub(offset:Int, length:Int) : IInflateStream {
    return new StringInflateStream(this.buf, offset+this.offset, length);
  }
}


