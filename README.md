# zjvm

A toy implementation of the Java Virtual Machine (JVM) 7 specification written in Zig. This JVM can execute Java bytecode including object creation, method calls, and field access. It implements core JVM concepts like the heap, call frames, and method dispatch.

## Quickstart

Requires [Zig 0.15](https://ziglang.org/download/) if you are on Mac, you can run `brew install zig` and [Docker](https://docs.docker.com/get-started/get-docker/) is requireed.

```bash
docker run --rm -v $(pwd):/workspace -w /workspace openjdk:7 javac example/src/main/java/basic/*.java
zig build run -- example/src/main/java/basic Fibonacci
```

## Features

See [FEATURES.md](FEATURES.md) for a comprehensive list of implemented and planned JVM features.

## Build and Run

Compile the Java examples:
```bash
docker run --rm -v $(pwd):/workspace -w /workspace openjdk:7 javac example/src/main/java/basic/*.java
```

Build and run the Zig VM with the following examples:

Fibonacci
```bash
zig build run -- example/src/main/java/basic Fibonacci
```
Test example
```bash
zig build run -- example/src/main/java/basic Test
```
For Loop 
```bash
zig build run -- example/src/main/java/basic Loops
```
