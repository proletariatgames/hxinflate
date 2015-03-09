/*
 * Copyright (C)2005-2013 Haxe Foundation
 * Portions Copyright (C) 2013 Proletariat, Inc.
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */

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


