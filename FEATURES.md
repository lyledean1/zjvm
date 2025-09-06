# ZJVM Features Checklist

A comprehensive list of JVM features and their implementation status in this toy JVM.

## ✅ Core Runtime Features (Completed)

### Bytecode Execution
- [x] Basic instruction dispatch loop
- [x] Program counter (PC) management
- [x] Opcode parsing and execution
- [x] NOP instruction handling

### Data Types & Constants
- [x] Integer constants (iconst_m1, iconst_0-5)
- [x] Byte push (bipush)
- [x] Load constants from pool (ldc)
- [x] Integer arithmetic (iadd)

### Local Variables
- [x] Integer loads (iload_0, iload_1)
- [x] Reference loads (aload_0, aload_1)
- [x] Reference stores (astore_1)
- [x] Dynamic local variable allocation based on max_locals

### Stack Operations
- [x] Basic stack manipulation (dup)
- [x] Operand stack management
- [x] Stack frame creation and management

### Method Invocation
- [x] Static method calls (invokestatic)
- [x] Instance method calls (invokespecial, invokevirtual)
- [x] Method parameter passing
- [x] Call frame management with locals
- [x] Constructor calls with 'this' reference

### Object System
- [x] Object creation (new)
- [x] Object reference storage
- [x] Instance field storage (putfield)
- [x] Instance field retrieval (getfield)
- [x] Heap-based object management
- [x] Object ID system

### Memory Management
- [x] Heap implementation
- [x] Object allocation and storage
- [x] Basic memory cleanup (deinit methods)

### Class System
- [x] Class loading from .class files
- [x] Constant pool parsing
- [x] Method table lookup
- [x] Field information storage
- [x] Class repository management

### Built-in Support
- [x] System.out.println mock implementation
- [x] java.lang.Object.<init> no-op handling
- [x] MockStringBuilder implementation (append, toString methods)

## ❌ Missing Core Features

### Data Types
- [ ] Long integers (lconst, lload, lstore, ladd, etc.)
- [ ] Floating point (fconst, fload, fstore, fadd, etc.)
- [ ] Double precision (dconst, dload, dstore, dadd, etc.)
- [ ] Boolean operations
- [ ] Character handling
- [ ] Short integer support

### Control Flow
- [x] Conditional branches (if_icmpeq, if_icmpne, if_icmplt, if_icmpge, if_icmpgt, if_icmple)
- [x] Simple conditional jumps (ifeq, ifne, iflt, ifge, ifgt, ifle)
- [x] Unconditional jumps (goto)
- [ ] Switch statements (tableswitch, lookupswitch)
- [x] Loops (while, for) - implemented via conditional branches and goto

### Arrays
- [ ] Array creation (anewarray, newarray)
- [ ] Array access (aaload, aastore, iaload, iastore)
- [ ] Array length (arraylength)
- [ ] Multi-dimensional arrays

### Exception Handling
- [ ] Exception throwing (athrow)
- [ ] Try-catch blocks
- [ ] Exception table parsing
- [ ] Finally block support
- [ ] Built-in exception classes (NullPointerException, etc.)

### Advanced Object Features
- [ ] Inheritance and super calls
- [ ] Virtual method dispatch
- [ ] Interface implementation
- [ ] instanceof checks
- [ ] Type casting (checkcast)

### String Support
- [ ] String objects (proper java.lang.String)
- [ ] String concatenation
- [ ] String constants in heap

### Static Features
- [ ] Static field access (getstatic, putstatic) - partially done
- [ ] Class initialization (<clinit>)
- [ ] Static blocks

### Method Features
- [ ] Method return types beyond void/int
- [ ] Method overloading resolution
- [ ] Native method support

### Memory
- [ ] Garbage collection

## 🔧 Quality of Life Features

### Debugging & Diagnostics
- [x] Debug mode with instruction tracing
- [ ] Stack trace generation
- [ ] Memory usage reporting
- [ ] Performance profiling

### Error Handling
- [x] Basic error reporting
- [ ] Comprehensive error messages
- [ ] Recovery from errors