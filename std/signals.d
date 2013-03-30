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
import core.atomic;

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
  *	- DONE: Handle slots removing/adding slots to the signal. (My current idea will enable adding/removing but will throw an exception if a slot calls emit.)
  *     - DONE: emit called while in emit would easily be possible with fibers, two solutions:
            - simply allow it. Meaning that the second emit is executed before the first one has finished.
            - queue it and execute it, when the first one has finished.
            The second one is more complex to implement, but seems to be the better solution. In fact it is not, because you basically serialize multiple fibers which can pretty much make them useless. In the first case, the slot has to handle the case when being called before an io operation is finished but this also means that it can do load balancing or whatever. With the queue implementation the access would just be serialized and the slot implementation could not do anything about it. So in fact the first implementation is also the expected one, even in the case of fibers.
  *	- DONE: Reduce memory usage by using a single array.
  *	- DONE: Ensure correctness on exceptions (chain them)
  *	- DONE (just did it): Checkout why I should use ==class instead of : Object and do it if it improves things
  * - DONE: Add strongConnect() method.
  * - CANCELED (keep it simple, functionality can be implemented in wrapper delegates if needed): Block signal functionality?
  *	- TODO: Think about const correctness
  * - DONE: Implement postblit and op assign & write unittest for these.
  * - TODO: Document not to rely on order in which the slots are called.
  *	- TODO: Mark it as trusted
  *	- TODO: Write unit tests
  * - DONE: Factor out template agnostic code to non templated code. (Use casts) 
  *     -> Avoids template bloat
  *     -> We can drop linkin()
  * - DONE: Provide a mixin wrapper, so only the containing object can emit a signal, with no additional work needed.
  *	- TODO: Rename it to std.signals2
  *	- TODO: Update documentation
  *	- TODO: Fix coding style to style guidlines of phobos.
  * - TODO: Document design decisions:
        - Why use mixin: So only containing object can emit signals+ copying a signal is not possible.
        - Performance wise: Optimize for very small empty signal, it should be no more than pointer+length. connect/disconnect is optimized to be fast in the case that emit is not currently running. Memory allocation is only done if active.
  *	- Get it into review for phobos :-)
  * - TODO: See if issue 4150 is still present.
  * - TODO:  Check documenation generated by DDOC and improve it.
  * - TODO:  Have it reviewed
  * - TODO: Get it into phobos.
  */
/**
  * Convenience wrapper mixin.
  * It allows you to do someobject.signal.connect() without allowing you to call emit, which only the containing object can.
  * It offers access to the underlying signal object via full (only for the containing object) or restricted for public access.
  */
mixin template Signal(Args...)
{
    private final void emit( Args args )
    {
        full.emit(args);
    }
    final void connect(string method, ClassType)(ClassType obj) if(is(ClassType == class) && __traits(compiles, {void delegate(Args) dg=mixin("&obj."~method);}))
    {
        full.connect!(method, ClassType)(obj);
    }
    final void connect(ClassType)(ClassType obj, void delegate(ClassType obj, Args) dg) if(is(ClassType == class))
    {
        full.connect!ClassType(obj, dg);
    }
    final void strongConnect(void delegate(Args) dg)
    {
        full.strongConnect(dg);
    }
    final void disconnect(string method, ClassType)(ClassType obj) if(is(ClassType == class) && __traits(compiles, {void delegate(Args) dg=mixin("&obj."~method);}))
    {
        full.disconnect!(method, ClassType)(obj);
    }
    final void disconnect(ClassType)(ClassType obj, void delegate(ClassType, T1) dg) if(is(ClassType == class))
    {
        full.disconnect!(ClassType)(obj, dg);
    }
    final void disconnect(ClassType)(ClassType obj) if(is(ClassType == class)) 
    {
        full.disconnect!ClassType(obj);
    }
    final void strongDisconnect(void delegate(Args) dg)
    {
        full.strongDisconnect(dg);
    }
    final ref RestrictedSignal!(Args) restricted() @property
    {
        return full.restricted;
    }
    private FullSignal!(Args) full;
}

struct FullSignal(Args...)
{
    alias restricted this;

    void emit( Args args )
    {
        restricted_.impl_.emit(args);
    }

    ref RestrictedSignal!(Args) restricted() @property
    {
        return restricted_;
    }

    private:
    RestrictedSignal!(Args) restricted_;
}
struct RestrictedSignal(Args...)
{
    /**
      * Direct connection to an object.
      *
      * Use this method if you want to connect directly to an objects method matching the signature of this signal.
      * The connection will have weak reference semantics, meaning if you drop all references to the object the garbage
      * collector will collect it and this connection will be removed.
      * Preconditions: obj must not be null. mixin("&obj."~method) must be valid and compatible.
      * Params:
      *     obj = Some object of a class implementing a method compatible with this signal.
      */
    void connect(string method, ClassType)(ClassType obj) if(is(ClassType == class) && __traits(compiles, {void delegate(Args) dg=mixin("&obj."~method);}))
    in
    {
        assert(obj);
    }
    body
    {
        impl_.addSlot(obj, cast(void delegate())mixin("&obj."~method));
    }
    /**
      * Indirect connection to an object.
      *
      * Use this overload if you want to connect to an object method which does not match the signals signature.
      * You can provide any delegate to do the parameter adaption, but make sure your delegates' context does not contain a reference
      * to the target object, instead use the provided obj parameter, where the object passed to connect will be passed to your delegate.
      * This is to make weak ref semantics possible, if your delegate contains a ref to obj, the object won't be freed as long as
      * the connection remains.
      *
      * Preconditions: obj and dg must not be null (dg's context may). dg's context must not be equal to obj.
      *
      * Params:
      *     obj = The object to connect to. It will be passed to the delegate when the signal is emitted.
      *     dg  = A wrapper delegate which takes care of calling some method of obj. It can do any kind of parameter adjustments necessary.
     */
    void connect(ClassType)(ClassType obj, void delegate(ClassType obj, Args) dg) if(is(ClassType == class))
    in
    {
        assert(obj);
        assert(dg);
        assert(cast(void*)obj != dg.ptr);
    }
    body
    {
        impl_.addSlot(obj, cast(void delegate()) dg);
    }

    /**
      * Connect with strong ref semantics.
      *
      * Use this overload if you either really really want strong ref semantics for some reason or because you want
      * to connect some non-class method delegate. Whatever the delegates context references, will stay in memory
      * as long as the signals connection is not removed and the signal gets not destroyed itself.
      *
      * Preconditions: dg must not be null. (Its context may.)
      *
      * Params:
      *     dg = The delegate to be connected.
      */
    void strongConnect(void delegate(Args) dg)
    in
    {
        assert(dg);
    }
    body
    {
        impl_.addSlot(null, cast(void delegate()) dg);
    }


    /**
      * Disconnect a direct connection.
      *
      * After issuing this call method of obj won't be triggered any longer when emit is called.
      * Preconditions: Same as for direct connect.
      */
    void disconnect(string method, ClassType)(ClassType obj) if(is(ClassType == class) && __traits(compiles, {void delegate(Args) dg=mixin("&obj."~method);}))
    in
    {
        assert(obj);
    }
    body
    {
        void delegate(Args) dg=mixin("&obj."~method);
        impl_.removeSlot(obj, cast(void delegate()) dg);
    }

    /**
      * Disconnect an indirect connection.
      *
      * For this to work properly, dg has to be exactly the same as the one passed to connect. So if you used a lamda
      * you have to keep a reference to it somewhere, if you want to disconnect the connection later on.
      * If you want to remove all connections to a particular object use the overload which only takes an object paramter.
     */
    void disconnect(ClassType)(ClassType obj, void delegate(ClassType, T1) dg) if(is(ClassType == class))
    in
    {
        assert(obj);
        assert(dg);
    }
    body
    {
        impl_.removeSlot(obj, cast(void delegate())dg);
    }

    /**
      * Disconnect all connections to obj.
      *
      * All connections to obj made with calls to connect are removed. 
     */
    void disconnect(ClassType)(ClassType obj) if(is(ClassType == class)) 
    in
    {
        assert(obj);
    }
    body
    {
        impl_.removeSlot(obj);
    }
    
    /**
      * Disconnect a connection made with strongConnect.
      *
      * Disconnects all connections to dg.
      */
    void strongDisconnect(void delegate(Args) dg)
    in
    {
        assert(dg);
    }
    body
    {
        impl_.removeSlot(null, cast(void delegate()) dg);
    }
    private:
    shared SignalImpl impl_;
}

private shared struct SignalImpl
{
    /**
      * Forbit copying.
      *
      * As struct must be relocatable it is not even possible to provide proper copy support for signals.
      * (rt_attachDisposeEvent is used for registering unhook. D's move semantics assume relocatable objects, which results
      * in this(this) being called for one instance and the destructor for another, thus the wrong handlers are deregistered.)
      * Not even destructive copy semantics are really possible, if you want to be safe, because of the explicit move() call.
      * So even if this(this) immediately drops the array and does not register unhook, D's assumption of relocatable objects is not
      * matched, so move() for example will still simply swap contents of two structs resulting in the wrong unhook delegates
      * being unregistered.
      */
    @disable this(this);
    /// Forbit copying, it does not work. See this(this).
    @disable void opAssign(SignalImpl other);

    void emit(Args...)( Args args )
    {
        auto slots=slots_; // copy, so removeSlot won't set it to null, after we checked it is not.
        if(!slots)
            return;
        doEmit((*slots)[], null, args);
    }

    void addSlot(Object obj, void delegate() dg)
    {
        SlotImpl* new_slot=null;
        shared SlotImpl* old_tail;
        auto slots=slots_; // So we can handle slots_ getting null concurrently.
        do 
        {
            if(!slots)  
            {
                slots=cast(shared)new SlotList(cast(shared)SlotImpl(obj, dg));
                break;
            }
            if(!new_slot)
                new_slot=new SlotImpl(obj, dg);
            old_tail=slots.tail;
            assert(old_tail);
            old_tail.next=cast(shared)new_slot;
        }
        while(!cas(&slots.tail, old_tail, cast(shared)new_slot));

        if(!slots_)  // Handle case that slots_ was set to null while we were operating on slots.
        {
            if(slots.tail!=&slots.head) // Everything got deleted, so keep it that way.
            {
                slots.head=*slots.tail;
                slots.tail=&slots.head;
            }
            slots_=slots;
        }
        assert(slots_ is slots); // Must be the same, regardless of what happened.

        if(obj) 
            rt_attachDisposeEvent(cast(Object)obj, cast(void delegate(Object o)) &unhook);
    }
    void removeSlot(Object obj, void delegate() dg)
    {
        auto removal=SlotImpl(obj, dg);
        removeSlot((item) => removal is item);
    }
    void removeSlot(Object obj, bool detach=true) 
    {
        removeSlot((item) => item.obj is obj);
    }
    /* **
     * Special function called when o is destroyed.
     * It causes any slots dependent on o to be removed from the list
     * of slots to be called by emit().
     */
    void unhook(Object o)
    {
        debug (signal) writefln("Unhooked object %s, for signal %s", cast(void*)o, &this);
        removeSlot(o, false);
    }

    ~this()
    {
        if(!slots_)
            return;
        foreach (slot; (*slots_)[])
        {
            debug (signal) stderr.writeln("Destruction, removing some slot, signal: ", &this);
            auto nslot=cast(SlotImpl*)slot;
            Object o=nslot.obj;
            if (nslot.isValid && o)
            {   
                rt_detachDisposeEvent(o, cast(void delegate(Object o)) &unhook); // Avoid dangling references.
            }
        }
    }
    private: // Private is more of a documentation in an already private context. Stuff not meant to be used outside this struct:
    void removeSlot(bool delegate(SlotImpl) isRemoved, bool detach=true)
    {
        auto slots=slots_; // Private copy, so it does not get suddenly set to null.
        if(!slots_)
            return;
        SlotImpl* prev=null;
        bool done;
        do 
        {
            done=true;
            foreach(slot; (*slots)[]) 
            {
                auto nslot=cast(SlotImpl*)slot;
                auto o=nslot.obj; // Won't get deleted now.
                if(!nslot.isValid) // Oops too late ...
                    continue;
                if(isRemoved(*nslot)) 
                {
                    if(!slots_)
                        return;  // GC was faster.
                    SlotImpl* next=nslot.next;
                    Object keepInMem;
                    do 
                    {
                        while(next && !next.isValid)
                            next=next.next;
                        if(!next) 
                            break;
                        keepInMem=next.obj;
                    }
                    while(!next.isValid);

                    if(prev) 
                    {
                        auto keepPreviousInMem=prev.obj;
                        if(!prev.isValid) // Removal not possible, prev got already removed by GC, try again. (If this condition is ever true when the GC is calling this function, we would have an andless loop -> Make sure this can not happen!)
                            // It can not, because prev.next was set to next before slot.makeInvalid() gets called also as we keep a reference to the next slots object, it can not be collected until we are done.
                        {
                            done=false;
                            break;
                        }
                        prev.next=next;
                        cas(&slots.tail, slot, cast(shared)prev);  // Don't check for slot.next!=null instead! (Important if concurrent to addSlot())
                        nslot.makeInvalid();
                    }
                    else 
                    {
                        if(next)
                        {
                            auto snext=cast(shared) next;
                            next=null;
                            slots.head=*snext;
                            if(slots.tail==snext)
                                slots.tail=&slots.head;
                        }
                        else 
                            slots_=null;
                    }
                    if(o && detach)  
                        rt_detachDisposeEvent(o, cast(void delegate(Object))&unhook);
                }
                else 
                    prev=nslot;
            }
        }
        while(!done);
    }

    // Helper method to allow all slots being called even in case of an exception. 
    // All exceptions that occur will be chained.
    void doEmit(Args...)( shared SlotList.Range slots, shared SlotImpl* previous, Args args )
    {
        scope (exit) 
        {
            if(!slots.empty)  
            {
                previous=slots.front; 
                slots.popFront(); 
                doEmit(slots, previous, args); // Carry on.
            }
        }
        for(; !slots.empty; slots.popFront())  // Explicit loop to avoid copy of range. (We need it to be advanced in scope(exit) )
        {
            Object o;
            auto nfront=cast(SlotImpl*)slots.front;
            do {
                o=nfront.obj; // From now on the current slot won't get deleted by GC.
            }
            while(nfront.obj!=o); // Can happen if front is slots_.head.

            if(nfront.isValid) // If it is valid now, then it stays valid, we hold a reference!
            {
                (*nfront)(o, args);
            }
            previous=slots.front;
        }
    }

    shared SlotList* slots_;
}

private shared struct SlotList {
    shared SlotImpl head;
    shared SlotImpl* tail;

    this(shared SlotImpl myHead) {
        head=myHead;
        tail=&head;
    }

    static shared struct Range {
        shared(SlotImpl*) front() @property {
            return current_;
        }
        void popFront() {
            assert(current_);
            current_=current_.next;
        }
        bool empty() @property {
            return current_==null || current_.next==null;
        }
        private shared SlotImpl* current_=null;
    }
    shared(Range) opSlice() {
        return Range(&head);
    }
}

// Simple convenience struct for signal implementation.
// Its is inherently unsafe. It is not a template so SignalImpl does not need to be one.
private struct SlotImpl 
{
    // Pass null for o if you have a strong ref delegate.
    this(Object o, void delegate() dg) 
    {
        obj=o;
        dg_= dg;
        if(o && dg_.ptr is cast(void*) o) 
            dg_.ptr=direct_ptr_flag;

    }
    @property Object obj() 
    {
        return obj_.obj;
    }
    @property obj(Object o)  
    {
        obj_.obj=o;
    }

    // For detecting that a slot got deleted.
    bool isValid() @property {
        return dg_.funcptr!=null;
    }

    void makeInvalid() {
        dg_.funcptr=null;
    }
    /// Takes o explicitely, because caller has to hold a strong ref to the object before calling this function is safe.
    void opCall(Args...)(Object o, Args args) 
    {
        assert(dg_);
        void* o_addr=cast(void*)(o);
        if(dg_.ptr is direct_ptr_flag || o_addr is strong_ptr_flag) 
        {
            auto mdg=cast(void delegate(Args)) dg_;
            if(o_addr !is strong_ptr_flag)
                mdg.ptr=cast(void*)o;
            mdg(args);
        }
        else 
        {
            auto mdg=cast(void delegate(Object, Args)) dg_;
            mdg(o, args);
        }

    }
    SlotImpl* next;
    private:
    void delegate() dg_;
    InvisibleRef obj_;

    enum direct_ptr_flag=cast(void*)(~0);
    enum strong_ptr_flag=null;
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
            auto tmp = cast(void*)(obj_high_<<16 | (obj_low_ & 0x0000ffff));
        return cast(Object)(tmp);
    }
    @property void obj(Object o) 
    {
        version (D_LP64) 
        {
            auto tmp = ~cast(ptrdiff_t)(cast(void*)o); // Invert pointer, so it is not in garbage collected memory.
            obj_= cast(void*)(tmp); 
        }
        else {
            auto tmp = cast(ptrdiff_t) cast(void*) o;
            obj_high_ = (tmp>>16)&0x0000ffff | 0xffff0000; // Address relies in kernel space
            obj_low_ = tmp&0x0000ffff | 0xffff0000;
        }
        assert(obj is o);
    }
    private:
    version(D_LP64) 
    {
        void* obj_=cast(void*)~cast(ptrdiff_t)(0);
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

        mixin Signal!(string, int) extendedSig;
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

        mixin Signal!(string, int)  s1;
        mixin Signal!(string, int)  s2;
        mixin Signal!(string, long) s3;
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

        mixin Signal!(string, int)  s4;
        mixin Signal!(string, int)  s5;
        mixin Signal!(string, long) s6;
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

version(none) { // Disabled because of dmd @@@BUG7758@@@
unittest 
{
    import std.stdio;

    struct Property 
    {
        alias value this;
        mixin Signal!(int) signal;
        @property int value() 
        {
            return value_;
        }
        ref Property opAssign(int val) 
        {
            debug (signal) writeln("Assigning int to property with signal: ", &this);
            value_=val;
            signal.emit(val);
            return this;
        }
        private: 
        int value_;
    }

    void observe(int val)
    {
        debug (signal) writefln("observe: Wow! The value changed: %s", val);
    }

    class Observer 
    {
        void observe(int val)
        {
            debug (signal) writefln("Observer: Wow! The value changed: %s", val);
            debug (signal) writefln("Really! I must know I am an observer (old value was: %s)!", observed);
            observed=val;
            count++;
        }
        int observed;
        int count;
    }
    Property prop;
    void delegate(int) dg=(val) => observe(val);
    prop.signal.strongConnect(dg);
    assert(prop.signal.full.impl_.slots_.length==1);
    Observer o=new Observer;
    prop.signal.connect!"observe"(o);
    assert(prop.signal.full.impl_.slots_.length==2);
    debug (signal) writeln("Triggering on original property with value 8 ...");
    prop=8;
    assert(o.count==1);
    assert(o.observed==prop);
}
}
unittest 
{
    import std.conv;
    FullSignal!() s1;
    void testfunc(int id) 
    {
        throw new Exception(to!string(id));
    }
    s1.strongConnect(() => testfunc(0));
    s1.strongConnect(() => testfunc(1));
    s1.strongConnect(() => testfunc(2));
    try {
        s1.emit();
    }
    catch(Exception e) {
        Throwable t=e;
        int i=0;
        while(t) {
            debug (signal) stderr.writefln("Caught exception (this is fine)");
            assert(to!int(t.msg)==i);
            t=t.next;
            i++;
        }
        assert(i==3);
    }
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
