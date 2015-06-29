/*
 * Copyright (C) 2013 Proletariat, Inc.
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
package serialization.internal;

import serialization.stream.IInflateStream;

using StringTools;

// https://en.m.wikipedia.org/wiki/Compact_prefix_tree
class RadixTree
{
  public var root(default, null):RadixNode;
  var m_map:Array<RadixNode>;
  var shash:Map<String,Int>;
  var scount:Int;
  var scache:Array<String>;
  var lastOffset:Int = 0;

  public function new() {
    m_map = [];
    shash = new Map();
    scount = 0;
    scache = [];
    this.root = createNode("");
  }

  public function serialize(word:String, buf:StringBuf, includeExisting:Bool) : Int {
    for (child in this.root.children) {
      var id = serialize_(word, 0, child, buf, includeExisting);
      if (id >= 0) {
        return id;
      }
    }

    var newBranch = createNode(word);
    newBranch.parent = this.root;
    this.root.children.push(newBranch);

    buf.add("!");
    addInt(buf, this.root.id-this.lastOffset);
    lastOffset = this.root.id;
    buf.add(":");
    addInt(buf, newBranch.data.length);
    buf.add(":");
    addStr(buf, newBranch.data);

    return newBranch.id;
  }

  function serialize_(word:String, start:Int, cur:RadixNode, buf:StringBuf, includeExisting:Bool) : Int {
    var num = findConsecutiveMatch(word, start, cur.data);
    if (num == 0) {
      return -1;
    }

    if (num < cur.data.length) {
      var old = cur.data;
      // We matched part of the current node, we need to create a split
      var split = createNode(cur.data.substr(0,num));
      var newSuffix = createNode(word.substr(start+num));

      split.children = [cur, newSuffix];
      cur.data = cur.data.substr(num);

      cur.parent.children.remove(cur);
      split.parent = cur.parent;
      split.parent.children.push(split);
      cur.parent = split;
      newSuffix.parent = split;

      buf.add("#");
      addInt(buf, cur.id-this.lastOffset);
      this.lastOffset = cur.id;
      buf.add(":");
      addInt(buf, num);
      buf.add(":");
      addInt(buf, newSuffix.data.length);
      buf.add(":");
      addStr(buf, newSuffix.data);

      return newSuffix.id;
    } else if (start+num != word.length) {
      // Recurse
      for (child in cur.children) {
        var id = serialize_(word, start+num, child, buf, includeExisting);
        if (id >= 0) {
          return id;
        }
      }

      // Insert a new branch
      var newSuffix = createNode(word.substr(start+num));
      newSuffix.parent = cur;
      cur.children.push(newSuffix);
      buf.add("!");
      addInt(buf, cur.id-this.lastOffset);
      this.lastOffset = cur.id;
      buf.add(":");
      addInt(buf, newSuffix.data.length);
      buf.add(":");
      addStr(buf, newSuffix.data);

      return newSuffix.id;
    } else {
      if (includeExisting) {
        buf.add('~');
        addInt(buf, cur.id-this.lastOffset);
        this.lastOffset = cur.id;
      }
      return cur.id;
    }
  }

  public function getID(name:String) : Int {
    var cur = this.root;
    var len = name.length;
    var matched = 0;
    while (cur != null && matched < len) {
      var next = null;
      for (child in cur.children) {
        var n = findConsecutiveMatch(name, matched, child.data);
        if (n != 0 && n == child.data.length) {
          next = child;
          break;
        }
      }

      if (next != null) {
        cur = next;
        matched += next.data.length;
      } else {
        cur = null;
      }
    }

    return cur != null && matched == len ? cur.id : -1;
  }

  @:access(serialization.Inflater)
  public function unserialize(inflater:Inflater, relative:Bool) : String {
    if (!relative) {
      this.lastOffset = 0;
    }

    var stm = inflater.stream;
    var code = stm.readByte();
    if (code == '#'.code) {
      // split
      var id = inflater.readDigits()+this.lastOffset;
      this.lastOffset = id;

      var cur = m_map[id];
      if (stm.readByte() != ':'.code) {
        throw 'invalid RadixTree code';
      }

      var num = inflater.readDigits();
      if (stm.readByte() != ':'.code) {
        throw 'invalid RadixTree code';
      }

      var len = inflater.readDigits();
      if (stm.readByte() != ':'.code) {
        throw 'invalid string length';
      }

      var str = stm.readString(len);

      var split = createNode(cur.data.substr(0,num));
      var newSuffix = createNode(str);
      cur.data = cur.data.substr(num);

      split.children = [cur, newSuffix];

      cur.parent.children.remove(cur);
      split.parent = cur.parent;
      split.parent.children.push(split);
      cur.parent = split;
      newSuffix.parent = split;

      return uptree(newSuffix);
    } else if (code == '!'.code) {
      // insert
      var id = inflater.readDigits()+this.lastOffset;
      this.lastOffset = id;
      var cur = m_map[id];
      if (stm.readByte() != ':'.code) {
        throw 'invalid RadixTree code';
      }

      var len = inflater.readDigits();
      if (stm.readByte() != ':'.code) {
        throw 'invalid string length';
      }
      var str = stm.readString(len);

      var newSuffix = createNode(str);
      newSuffix.parent = cur;
      cur.children.push(newSuffix);

      return uptree(newSuffix);
    } else if (code == '~'.code) {
      var id = inflater.readDigits()+this.lastOffset;
      this.lastOffset = id;
      return uptree(m_map[id]);
    } else {
      throw 'unrecognized code $code';
    }
  }

  public inline function lookup(id:Int) : String {
    var node = m_map[id];
    if (node == null) {
      throw 'invalid radix node: $id';
    }
    return uptree(node);
  }

  function uptree(start:RadixNode) : String {
    if (start.cached != null) {
      return start.cached;
    }

    var nodes = [];
    var cur = start;
    var root = this.root;
    while (cur != root) {
      nodes.push(cur);
      cur = cur.parent;
    }
    var i = nodes.length;
    var buf = new StringBuf();
    while (i-- > 0) {
      buf.add(nodes[i].data);
    }

    return start.cached=buf.toString();
  }

  inline function createNode(part:String) : RadixNode {
    var node = new RadixNode(part, m_map.length);
    m_map.push(node);
    return node;
  }

  inline function findConsecutiveMatch(a:String, start:Int, b:String) : Int {
    var minLen = a.length-start;
    if (b.length < minLen) minLen = b.length;

    var matches = 0;
    for (i in 0...minLen) {
      if (a.fastCodeAt(start+i) == b.fastCodeAt(i)) {
        ++matches;
      } else {
        break;
      }
    }
    return matches;
  }

  // mini optimizations to improve codegen for JS
  static inline function addInt(buf:StringBuf, x:Int) {
    #if js
      untyped buf.b += x;
    #else
      buf.add(x);
    #end
  }
  static inline function addStr(buf:StringBuf, x:String) {
    #if js
      untyped buf.b += x;
    #else
      buf.add(x);
    #end
  }
}

private class RadixNode
{
  public var id:Int;
  public var data:String;
  public var cached:String;
  public var parent:RadixNode;
  public var children:Array<RadixNode>;

  public function new(data:String, id:Int) {
    this.cached = null;
    this.id = id;
    this.data = data;
    this.parent = null;
    this.children = [];
  }
}


