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

package utils;

import utils.Inflater;
import model.Result;
import haxe.io.*;
import sys.io.*;

/** Implementation of IInflateStream around a haxe file handle */
class HaxeFileInflateStream implements IInflateStream
{
  var path:String;
  var stm:FileInput;
  var offset:Int;
  var length:Int;

  public function new(filename:String, ?offset:Int=0, ?length:Int=-1) {
    this.path = filename;
    this.stm = File.read(filename);
    setOffsetLength(offset, length);
  }

  function setOffsetLength(offset:Int, length:Int) {
    this.offset = offset;
    this.length = length;
    if (this.length < 0) {
      this.stm.seek(0, SeekEnd);
      this.length = this.stm.tell();
    }

    this.stm.seek(offset, SeekBegin);
  }

  public function readAndDispose() : Result<String> {
    dispose();
    try {
      var s = File.getContent(path);
      return Success(s);
    } catch (e:Dynamic) {
      return Error(Std.string(e));
    }
  }

  public function dispose() : Void {
    stm.close();
    stm = null;
  }

  public function getPos() : Int {
    var pos:Int = this.stm.tell();
    return pos - this.offset;
  }

  public function seekTo(pos:Int) : Void {
    this.stm.seek(this.offset+pos, SeekBegin);
  }

  public function peekByte() : Int {
    var b = stm.readByte();
    this.stm.seek(-1, SeekCur);
    return b;
  }

  public function readByte() : Int {
    return stm.readByte();
  }

  public function readString(len:Int) : String {
    return this.stm.readString(len);
  }

  public function sub(offset:Int, length:Int) : IInflateStream {
    return new HaxeFileInflateStream(this.path, this.offset+offset, length);
  }

  public function getLength() : Int {
    return this.length;
  }

  public function eof() : Bool {
    return getPos() >= this.length;
  }
}

