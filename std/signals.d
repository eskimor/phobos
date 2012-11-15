// Written in the D programming language.

/**
 * Signals and Slots are an implementation of the Observer Pattern.
 * Essentially, when a Signal is emitted, a list of connected Observers
 * (called slots) are called.
 *
 * There have been several D implementations of Signals and Slots.
 * This version makes use of several new features in D, which make
 * using it simpler and less error prone. In particular, it is no
 * longer necessary to instrument the slots.
 *
 * References:
 *      $(LUCKY A Deeper Look at Signals and Slots)$(BR)
 *      $(LINK2 http://en.wikipedia.org/wiki/Observer_pattern, Observer pattern)$(BR)
 *      $(LINK2 http://en.wikipedia.org/wiki/Signals_and_slots, Wikipedia)$(BR)
 *      $(LINK2 http://boost.org/doc/html/$(SIGNALS).html, Boost Signals)$(BR)
 *      $(LINK2 http://doc.trolltech.com/4.1/signalsandslots.html, Qt)$(BR)
 *
 *      There has been a great deal of discussion in the D newsgroups
 *      over this, and several implementations:
 *
 *      $(LINK2 http://www.digitalmars.com/d/archives/digitalmars/D/announce/signal_slots_library_4825.html, signal slots library)$(BR)
 *      $(LINK2 http://www.digitalmars.com/d/archives/digitalmars/D/Signals_and_Slots_in_D_42387.html, Signals and Slots in D)$(BR)
 *      $(LINK2 http://www.digitalmars.com/d/archives/digitalmars/D/Dynamic_binding_--_Qt_s_Signals_and_Slots_vs_Objective-C_42260.html, Dynamic binding -- Qt's Signals and Slots vs Objective-C)$(BR)
 *      $(LINK2 http://www.digitalmars.com/d/archives/digitalmars/D/Dissecting_the_SS_42377.html, Dissecting the SS)$(BR)
 *      $(LINK2 http://www.digitalmars.com/d/archives/digitalmars/D/dwt/about_harmonia_454.html, about harmonia)$(BR)
 *      $(LINK2 http://www.digitalmars.com/d/archives/digitalmars/D/announce/1502.html, Another event handling module)$(BR)
 *      $(LINK2 http://www.digitalmars.com/d/archives/digitalmars/D/41825.html, Suggestion: signal/slot mechanism)$(BR)
 *      $(LINK2 http://www.digitalmars.com/d/archives/digitalmars/D/13251.html, Signals and slots?)$(BR)
 *      $(LINK2 http://www.digitalmars.com/d/archives/digitalmars/D/10714.html, Signals and slots ready for evaluation)$(BR)
 *      $(LINK2 http://www.digitalmars.com/d/archives/digitalmars/D/1393.html, Signals &amp; Slots for Walter)$(BR)
 *      $(LINK2 http://www.digitalmars.com/d/archives/28456.html, Signal/Slot mechanism?)$(BR)
 *      $(LINK2 http://www.digitalmars.com/d/archives/19470.html, Modern Features?)$(BR)
 *      $(LINK2 http://www.digitalmars.com/d/archives/16592.html, Delegates vs interfaces)$(BR)
 *      $(LINK2 http://www.digitalmars.com/d/archives/16583.html, The importance of component programming (properties$(COMMA) signals and slots$(COMMA) etc))$(BR)
 *      $(LINK2 http://www.digitalmars.com/d/archives/16368.html, signals and slots)$(BR)
 *
 * Bugs:
 *      Slots can only be delegates formed from class objects or
 *      interfaces to class objects. If a delegate to something else
 *      is passed to connect(), such as a struct member function,
 *      a nested function or a COM interface, undefined behavior
 *      will result.
 *
 *      Not safe for multiple threads operating on the same signals
 *      or slots.
 * Macros:
 *      WIKI = Phobos/StdSignals
 *      SIGNALS=signals
 *
 * Copyright: Copyright Digital Mars 2000 - 2009.
 * License:   <a href="http://www.boost.org/LICENSE_1_0.txt">Boost License 1.0</a>.
 * Authors:   $(WEB digitalmars.com, Walter Bright)
 * Source:    $(PHOBOSSRC std/_signals.d)
 */
/*          Copyright Digital Mars 2000 - 2009.
 * Distributed under the Boost Software License, Version 1.0.
 *    (See accompanying file LICENSE_1_0.txt or copy at
 *          http://www.boost.org/LICENSE_1_0.txt)
 */
module std.signals;

import std.stdio;
import std.c.stdlib : calloc, realloc, free;
import core.exception : onOutOfMemoryError;

// Special function for internal use only.
// Use of this is where the slot had better be a delegate
// to an object or an interface that is part of an object.
extern (C) Object _d_toObject(void* p);

// Used in place of Object.notifyRegister and Object.notifyUnRegister.
alias void delegate(Object) DisposeEvt;
extern (C) void  rt_attachDisposeEvent( Object obj, DisposeEvt evt );
extern (C) void  rt_detachDisposeEvent( Object obj, DisposeEvt evt );
//debug=signal;

/************************
 * Mixin to create a signal within a class object.
 *
 * Different signals can be added to a class by naming the mixins.
 *
 * Example:
---
import std.signals;
import std.stdio;

class Observer
{   // our slot
    void watch(string msg, int i)
    {
        writefln("Observed msg '%s' and value %s", msg, i);
    }
}

class Foo
{
    int value() { return _value; }

    int value(int v)
    {
        if (v != _value)
        {   _value = v;
            // call all the connected slots with the two parameters
            emit("setting new value", v);
        }
        return v;
    }

    // Mix in all the code we need to make Foo into a signal
    mixin Signal!(string, int);

  private :
    int _value;
}

void main()
{
    Foo a = new Foo;
    Observer o = new Observer;

    a.value = 3;                // should not call o.watch()
    a.connect(&o.watch);        // o.watch is the slot
    a.value = 4;                // should call o.watch()
    a.disconnect(&o.watch);     // o.watch is no longer a slot
    a.value = 5;                // so should not call o.watch()
    a.connect(&o.watch);        // connect again
    a.value = 6;                // should call o.watch()
    destroy(o);                 // destroying o should automatically disconnect it
    a.value = 7;                // should not call o.watch()
}
---
 * which should print:
 * <pre>
 * Observed msg 'setting new value' and value 4
 * Observed msg 'setting new value' and value 6
 * </pre>
 *
 */

/**
  * Todo:
  *	- Handle slots removing/adding slots to the signal. (My current idea will enable adding/removing but will throw an exception if a slot calls emit.)
  *     - emit called while in emit would easily be possible with fibers, two solutions:
            - simply allow it. Meaning that the second emit is executed before the first one has finished.
            - queue it and execute it, when the first one has finished.
            The second one is more complex to implement, but seems to be the better solution. In fact it is not, because you basically serialize multiple fibers which can pretty much make them useless. In the first case, the slot has to handle the case when being called before an io operation is finished but this also means that it can do load balancing or whatever. With the queue implementation the access would just be serialized and the slot implementation could not do anything about it. So in fact the first implementation is also the expected one, even in the case of fibers.
  *	- DONE: Reduce memory usage by using a single array.
  *	- Ensure correctness on exceptions (chain them)
  *	- Checkout why I should use ==class instead of : Object and do it if it improves things
  * - Add strongConnect() method.
  * - Block signal functionality?
  *	- Think about const correctness
  * - Implement postblit and op assign & write unittest for these.
  *	- Mark it as trusted
  *	- Write unit tests
  * - Factor out template agnostic code to non templated code. (Use casts) 
  *     -> Avoids template bloat
  *     -> We can drop linkin()
  * - Provide a mixin wrapper, so only the containing object can emit a signal, with no additional work needed.
  *	- Rename it to std.signals2
  *	- Update documentation
  *	- Fix coding style to style guidlines of phobos.
  * - Document design decisions:
        - Why use mixin: So only containing object can emit signals+ copying a signal is not possible.
        - Performance wise: Optimize for very small empty signal, it should be no more than pointer+length. connect/disconnect is optimized to be fast in the case that emit is not currently running. Memory allocation is only done if active.
  *	- Get it into review for phobos :-)
  */
struct Signal(T1...)
{
    static import std.c.stdlib;
    static import core.exception;

    /***
     * Call each of the connected slots, passing the argument(s) i to them.
	 * Todo: Handle exceptions: Make sure all slots are being called when an exception occurs. And rethrow a list
	 * of all exceptions.
     */
    void emit( T1 i )
    {
        debug (signal) writefln("Signal.emit()");
        foreach (slot; slots)
        {   
            if(slot.dg.indirect.ptr!=direct_ptr_flag) // It is an indirect call
            { 
                debug (signal) writefln("Signal.emit() indirect");
                slot.dg.indirect(slot.obj, i);
            }
            else // Direct call:
            { 
                debug (signal) writefln("Signal.emit() direct, obj: %s", slot.obj);
                auto dg=slot.dg.direct;
                dg.ptr=cast(void*)(slot.obj);
                dg(i);
            }
        }
    }
    private void addSlot(T2)(T2 obj, DelegateTypes dg)
    {
        debug (signal) writefln("Signal.addSlot(slot)");
        slots~=Slot(obj, dg);
        if(obj) {
            rt_attachDisposeEvent(obj, &unhook);
        }
    }
    void connect(string method, T2)(T2 obj) if(is(T2 : Object)) {
        debug (signal) writefln("Signal.connect(obj)");
        DelegateTypes t;
        t.direct=mixin("&obj."~method);
        t.direct.ptr=direct_ptr_flag; // Avoid a reference to the actual object. Don't use null: A delegate formed from a function will also have a null ptr.
        addSlot(obj, t);
    }
    /***
     * Add a slot to the list of slots to be called when emit() is called.
     */
    void connect(T2)(T2 obj, void delegate(T2 obj, T1) dg)
    {
        debug (signal) stderr.writefln("Signal.connect(delegate)");
        DelegateTypes t;
        t.indirect=cast(void delegate(Object, T1))(dg);
        addSlot(obj, t);
    }

    private void removeSlot(Object obj, DelegateTypes dgs=DelegateTypes(), bool detach=true)
    {
        debug (signal) writefln("Signal.disconnect(slot)");
        for(int i=0; i<slots.length; )
        {
            if (slots[i].obj is obj && (dgs==DelegateTypes() || slots[i].dg is dgs))
            {   
                slots[i]=slots[slots.length-1];
                slots.length=slots.length-1;
                slots.assumeSafeAppend();
                if(obj && detach)  {
                    rt_detachDisposeEvent(obj, &unhook);
                    debug (signal) writefln("Detached unhook to %s", obj);
                }
            }
            else
                i++;
        }
    }
    /***
     * Remove a slot from the list of slots to be called when emit() is called.
     * Warning: Don't rely on the order slots being called is the same they have been registered, this will break as soon a slot is deregistered.
     */
    void disconnect(T2)(T2 obj, void delegate(T2, T1) dg)
    {
        DelegateTypes t;
        t.indirect=cast(void delegate(Object, T1)) (dg);
        removeSlot(obj, dg);
    }

    void disconnect(string method, T2)(T2 obj) if(is(T2 : Object))
    {
        DelegateTypes t;
        t.direct=mixin("&obj."~method);
        t.direct.ptr=direct_ptr_flag;
        removeSlot(obj, t);
    }

    /// Easy disconnect a whole object.
    void disconnect(T2)(T2 obj) if(is(T2 : Object)) {
        assert(obj);
        removeSlot(obj);
    }

    /* **
     * Special function called when o is destroyed.
     * It causes any slots dependent on o to be removed from the list
     * of slots to be called by emit().
     */
    private void unhook(Object o)
    {
        removeSlot(o, DelegateTypes(), false);
    }

    /* **
     * There can be multiple destructors inserted by mixins.
     */
    ~this()
    {
        /* **
         * When this object is destroyed, need to let every slot
         * know that this object is destroyed so they are not left
         * with dangling references to it.
         */
        if (slots)
        {
            foreach (slot; slots)
            {
                if (slot.obj)
                {   
                    rt_detachDisposeEvent(slot.obj, &unhook);
                }
            }
            slots = null;
        }
    }
    private:
    Slot[] slots;
    // Value used for indicating that a direct delegate is in use:
    enum direct_ptr_flag=cast(void*)(~0);
    enum emit_in_progress=cast(void*)(~0-1);
    union DelegateTypes
    {
        void delegate(Object, T1) indirect;
        void delegate(T1) direct;
    }
    }
}
// A function whose sole purpose is to get this module linked in
// so the unittest will run.
void linkin() { }

private struct Slot {
    this(Object obj, DelegateTypes dg) 
    {
        this.obj=obj;
        this.dg=dg;
    }
    @property Object obj() 
    {
        return obj_.obj;
    }
    @property obj(Object o)  
    {
        obj_.obj=o;
    }
    DelegateTypes dg;
    private:
    InvisibleRef obj_;
}

// Provides a way of holding a reference to an object, without the GC seeing it.
private struct InvisibleRef
{
    this(Object o) 
    {
        obj=o;
    }
    @property Object obj() 
    {
        version (D_LP64) 
            auto tmp=cast(void*)(~cast(ptrdiff_t)obj_); //Invert pointer.
        else 
            auto tmp = cast(void*)(obj_high_<<16 | obj_low_);
        return cast(Object)(tmp);
    }
    @property void obj(Object o) 
    {
        version (D_LP64) 
        {
            auto tmp = ~cast(ptrdiff_t)(cast(void*)o); // Invert pointer, so it is not in garbage collected memory.
            obj_= cast(void*)(tmp); 
            rt_attachDisposeEvent(obj, &unhook);
        }
        else {
            auto tmp = cast(ptrdiff_t) cast(void*) o;
            obj_high_ = (tmp>>16)&0x0000ffff;
            obj_low_ = tmp&0x0000ffff;
        }
        assert(obj==o);
    }
    private:
    version(D_LP64) 
    {
        void* obj_;
    }
    else 
    {
        ptrdiff_t obj_high_;
        ptrdiff_t obj_low_;
    }
}
unittest
{
    class Observer
    {
        void watch(string msg, int i)
        {
            //writefln("Observed msg '%s' and value %s", msg, i);
            captured_value = i;
            captured_msg   = msg;
        }


        int    captured_value;
        string captured_msg;
    }

    class SimpleObserver 
    {
        void watchOnlyInt(int i) {
            captured_value=i;
        }
        int captured_value;
    }

    class Foo
    {
        @property int value() { return _value; }

        @property int value(int v)
        {
            if (v != _value)
            {   _value = v;
                extendedSig.emit("setting new value", v);
                //simpleSig.emit(v);
            }
            return v;
        }

        Signal!(string, int) extendedSig;
        //Signal!(int) simpleSig;

        private:
        int _value;
    }

    Foo a = new Foo;
    Observer o = new Observer;
    SimpleObserver so = new SimpleObserver;
    // check initial condition
    assert(o.captured_value == 0);
    assert(o.captured_msg == "");

    // set a value while no observation is in place
    a.value = 3;
    assert(o.captured_value == 0);
    assert(o.captured_msg == "");

    // connect the watcher and trigger it
    a.extendedSig.connect!"watch"(o);
    a.value = 4;
    assert(o.captured_value == 4);
    assert(o.captured_msg == "setting new value");

    // disconnect the watcher and make sure it doesn't trigger
    a.extendedSig.disconnect!"watch"(o);
    a.value = 5;
    assert(o.captured_value == 4);
    assert(o.captured_msg == "setting new value");
    //a.extendedSig.connect!Observer(o, (obj, msg, i) { obj.watch("Hahah", i); });
    a.extendedSig.connect!Observer(o, (obj, msg, i) => obj.watch("Hahah", i) );

    a.value=7;	
    debug (signal) stderr.writeln("After asignment!");
    assert(o.captured_value == 7);
    assert(o.captured_msg == "Hahah");
    a.extendedSig.disconnect(o); // Simply disconnect o, otherwise we would have to store the lamda somewhere if we want to disconnect later on.
    // reconnect the watcher and make sure it triggers
    a.extendedSig.connect!"watch"(o);
    a.value = 6;
    assert(o.captured_value == 6);
    assert(o.captured_msg == "setting new value");

    // destroy the underlying object and make sure it doesn't cause
    // a crash or other problems
    debug (signal) stderr.writefln("Disposing");
    destroy(o);
    debug (signal) stderr.writefln("Disposed");
    a.value = 7;
}

unittest {
    class Observer
    {
        int    i;
        long   l;
        string str;

        void watchInt(string str, int i)
        {
            this.str = str;
            this.i = i;
        }

        void watchLong(string str, long l)
        {
            this.str = str;
            this.l = l;
        }
    }

    class Bar
    {
        @property void value1(int v)  { s1.emit("str1", v); }
        @property void value2(int v)  { s2.emit("str2", v); }
        @property void value3(long v) { s3.emit("str3", v); }

        Signal!(string, int)  s1;
        Signal!(string, int)  s2;
        Signal!(string, long) s3;
    }

    void test(T)(T a) {
        auto o1 = new Observer;
        auto o2 = new Observer;
        auto o3 = new Observer;

        // connect the watcher and trigger it
        a.s1.connect!"watchInt"(o1);
        a.s2.connect!"watchInt"(o2);
        a.s3.connect!"watchLong"(o3);

        assert(!o1.i && !o1.l && !o1.str);
        assert(!o2.i && !o2.l && !o2.str);
        assert(!o3.i && !o3.l && !o3.str);

        a.value1 = 11;
        assert(o1.i == 11 && !o1.l && o1.str == "str1");
        assert(!o2.i && !o2.l && !o2.str);
        assert(!o3.i && !o3.l && !o3.str);
        o1.i = -11; o1.str = "x1";

        a.value2 = 12;
        assert(o1.i == -11 && !o1.l && o1.str == "x1");
        assert(o2.i == 12 && !o2.l && o2.str == "str2");
        assert(!o3.i && !o3.l && !o3.str);
        o2.i = -12; o2.str = "x2";

        a.value3 = 13;
        assert(o1.i == -11 && !o1.l && o1.str == "x1");
        assert(o2.i == -12 && !o1.l && o2.str == "x2");
        assert(!o3.i && o3.l == 13 && o3.str == "str3");
        o3.l = -13; o3.str = "x3";

        // disconnect the watchers and make sure it doesn't trigger
        a.s1.disconnect!"watchInt"(o1);
        a.s2.disconnect!"watchInt"(o2);
        a.s3.disconnect!"watchLong"(o3);

        a.value1 = 21;
        a.value2 = 22;
        a.value3 = 23;
        assert(o1.i == -11 && !o1.l && o1.str == "x1");
        assert(o2.i == -12 && !o1.l && o2.str == "x2");
        assert(!o3.i && o3.l == -13 && o3.str == "x3");

        // reconnect the watcher and make sure it triggers
        a.s1.connect!"watchInt"(o1);
        a.s2.connect!"watchInt"(o2);
        a.s3.connect!"watchLong"(o3);

        a.value1 = 31;
        a.value2 = 32;
        a.value3 = 33;
        assert(o1.i == 31 && !o1.l && o1.str == "str1");
        assert(o2.i == 32 && !o1.l && o2.str == "str2");
        assert(!o3.i && o3.l == 33 && o3.str == "str3");

        // destroy observers
        destroy(o1);
        destroy(o2);
        destroy(o3);
        a.value1 = 41;
        a.value2 = 42;
        a.value3 = 43;
    }

    test(new Bar);

    class BarDerived: Bar
    {
        @property void value4(int v)  { s4.emit("str4", v); }
        @property void value5(int v)  { s5.emit("str5", v); }
        @property void value6(long v) { s6.emit("str6", v); }

        Signal!(string, int)  s4;
        Signal!(string, int)  s5;
        Signal!(string, long) s6;
    }

    auto a = new BarDerived;

    test!Bar(a);
    test!BarDerived(a);

    auto o4 = new Observer;
    auto o5 = new Observer;
    auto o6 = new Observer;

    // connect the watcher and trigger it
    a.s4.connect!"watchInt"(o4);
    a.s5.connect!"watchInt"(o5);
    a.s6.connect!"watchLong"(o6);

    assert(!o4.i && !o4.l && !o4.str);
    assert(!o5.i && !o5.l && !o5.str);
    assert(!o6.i && !o6.l && !o6.str);

    a.value4 = 44;
    assert(o4.i == 44 && !o4.l && o4.str == "str4");
    assert(!o5.i && !o5.l && !o5.str);
    assert(!o6.i && !o6.l && !o6.str);
    o4.i = -44; o4.str = "x4";

    a.value5 = 45;
    assert(o4.i == -44 && !o4.l && o4.str == "x4");
    assert(o5.i == 45 && !o5.l && o5.str == "str5");
    assert(!o6.i && !o6.l && !o6.str);
    o5.i = -45; o5.str = "x5";

    a.value6 = 46;
    assert(o4.i == -44 && !o4.l && o4.str == "x4");
    assert(o5.i == -45 && !o4.l && o5.str == "x5");
    assert(!o6.i && o6.l == 46 && o6.str == "str6");
    o6.l = -46; o6.str = "x6";

    // disconnect the watchers and make sure it doesn't trigger
    a.s4.disconnect!"watchInt"(o4);
    a.s5.disconnect!"watchInt"(o5);
    a.s6.disconnect!"watchLong"(o6);

    a.value4 = 54;
    a.value5 = 55;
    a.value6 = 56;
    assert(o4.i == -44 && !o4.l && o4.str == "x4");
    assert(o5.i == -45 && !o4.l && o5.str == "x5");
    assert(!o6.i && o6.l == -46 && o6.str == "x6");

    // reconnect the watcher and make sure it triggers
    a.s4.connect!"watchInt"(o4);
    a.s5.connect!"watchInt"(o5);
    a.s6.connect!"watchLong"(o6);

    a.value4 = 64;
    a.value5 = 65;
    a.value6 = 66;
    assert(o4.i == 64 && !o4.l && o4.str == "str4");
    assert(o5.i == 65 && !o4.l && o5.str == "str5");
    assert(!o6.i && o6.l == 66 && o6.str == "str6");

    // destroy observers
    destroy(o4);
    destroy(o5);
    destroy(o6);
    a.value4 = 44;
    a.value5 = 45;
    a.value6 = 46;
}

version(none) // Disabled because of dmd @@@BUG5028@@@
unittest
{
    class A
    {
        mixin Signal!(string, int) s1;
    }

    class B : A
    {
        mixin Signal!(string, int) s2;
    }
}
/* vim: set ts=4 sw=4 expandtab : */
