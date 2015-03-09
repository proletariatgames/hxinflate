package serialization.stream;

/** Abstract implementation of a stream, passed to Inflater */
interface IInflateStream
{
  function getPos() : Int;
  function seekTo(pos:Int) : Void;
  function peekByte() : Int;
  function readByte() : Int;
  function readString(len:Int) : String;
  function getLength() : Int;
  function eof() : Bool;
  function sub(offset:Int, length:Int) : IInflateStream;
  function dispose() : Void;
}

