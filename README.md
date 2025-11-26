<div align="center">
<h1> QuickJS - KT </h1>
<img alt="Maven Central" src="https://img.shields.io/maven-central/v/io.github.dokar3/quickjs-kt?style=flat-square&color=%23ea197e">
<p>Run your JavaScript code in Kotlin, asynchronously.</p>
<img src="./media/async-eval-demo.gif" alt="The async eval demo">
</div>

## 🎉 Latest Update (v1.0.0-alpha14 - 2025-11-26)

### QuickJS Version Update
- ✅ Updated from `2024-02-14` to **`2025-04-26`** (latest version from [quickjs-zh](https://github.com/quickjs-zh/QuickJS))
- Includes latest QuickJS improvements and bug fixes
- Better performance and stability
- Support for latest ES2023+ features

### Android 64KB Page Size Support
- ✅ Added support for **Android 15+ 64KB page size**
- ✅ Ensures compatibility with new devices using 16KB page size
- Linker flag: `-Wl,-z,max-page-size=65536`

Starting from Android 15, some devices (especially those with new architectures) use 16KB page size instead of the traditional 4KB. To ensure forward compatibility, this library now builds with a maximum page size of 64KB.

**Verify the build:**
```bash
readelf -l libquickjs.so | grep LOAD
# Check that Align value is 0x10000 (64KB)
```

---

This is a [QuickJS](https://bellard.org/quickjs/) binding for idiomatic Kotlin, inspired by Cash App's [Zipline](https://github.com/cashapp/zipline) (previously Duktape Android) but with more flexibility.

### Another QuickJS wrapper?

There are a few QuickJS wrappers for Android already. Some written in Java are not Kotlin Multiplatform friendly, and some lack updates.

Zipline is great and KMP-friendly, but it focuses on running Kotlin/JS modules. Its API is limited to running arbitrary JavaScript code with platform bindings. 

That's why I created this library, with some good features:

- Simple and idiomatic Kotlin APIs, it's easy to define binding and evaluate arbitrary code
- Highly integrated with **Kotlin Coroutines**, it is `async` and `suspend`ed. See [#Async](#async)
- Kotlin Multiplatform targets, including `Android`, `JVM` and `Kotlin/Native`
- The latest version of QuickJS (2025-04-26) with Android 64KB page size support

# Usages

### Installation

In `build.gradle.kts`:

```kotlin
implementation("io.github.dokar3:quickjs-kt:<VERSION>")
```

Or in `libs.versions.toml`:

```toml
quickjs-kt = { module = "io.github.dokar3:quickjs-kt", version = "<VERSION>" }
```

### Evaluate

with DSL (This is recommended if you don't need long-live instances):

```kotlin
coroutineScope.launch {
    val result = quickJs {
        evaluate<Int>("1 + 2")
    }
}
```

without DSL:

```kotlin
val quickJs = QuickJs.create(Dispatchers.Default)

coroutineScope.launch {
    val result = quickJs.evaluate<Int>("1 + 2")
    quickJs.close()
}
```

Evaluate the compiled bytecode:

```kotlin
coroutineScope.launch {
    quickJs {
        val bytecode = compile("1 + 2")
        val result = evaluate<Int>(bytecode)
    }
}
```

### Bindings

With DSL:

```kotlin
quickJs {
    define("console") {
        function("log") { args ->
            println(args.joinToString(" "))
        }
    }

    function("fetch") { args ->
        someClient.request(args[0])
    }

    function<String, String>("greet") { "Hello, $it!" }

    evaluate<Any?>(
        """
        console.log("Hello from JavaScript!")
        fetch("https://www.example.com")
        greet("Jack")
        """.trimIndent()
    )
}
```

With Reflection (JVM only):

```kotlin
class Console {
    fun log(args: Array<Any?>) = TODO()
}

class Http {
    fun fetch(url: String) = TODO()
}

quickJs {
    define<Console>("console", Console())
    define<Http>("http", Http())

    evaluate<Any?>(
        """
        console.log("Hello from JavaScript!")
        http.fetch("https://www.example.com")
        """.trimIndent()
    )
}
```

Binding classes need to be added to Android's ProGuard rules files.

```
-keep class com.example.Console { *; }
-keep class com.example.Http { *; }
```

### Async

This library gives you the ability to define [async functions](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Reference/Statements/async_function). Within the `QuickJs` instance, a coroutine scope is created to launch async jobs, a job `Dispatcher` can also be passed when creating the instance.

`evaluate()` and `quickJs{}` are `suspend` functions, which make your async jobs await in the caller scope. All pending jobs will be canceled when the caller scope is canceled or the instance is closed.

To define async functions, easily call `asyncFunction()`:

```kotlin
quickJs {
    define("http") {
        asyncFunction("request") {
            // Call suspend functions here
        }
    }

    asyncFunction("fetch") {
        // Call suspend functions here
    }
}
```

In JavaScript, you can use the top level await to easily get the result:

```javascript
const resp = await http.request("https://www.example.com");
const next = await fetch("https://www.example.com");
```

Or use `Promise.all()` to run your request concurrently!

```javascript
const responses = await Promise.all([
    fetch("https://www.example.com/0"),
    fetch("https://www.example.com/1"),
    fetch("https://www.example.com/2"),
])
```

### Modules

[ES Modules](https://developer.mozilla.org/en-US/docs/Web/JavaScript/Guide/Modules) are supported when `evaluate()` or `compile()` has the parameter `asModule = true`. 

```kotlin
quickJs {
    // ...
    evaluate<String>(
        """
            import * as hello from "hello";
            // Use hello
        """.trimIndent(),
        asModule = true,
    )
}
```

Modules can be added using `addModule()`  functions, both code and QuickJS bytecode are supported.

```kotlin
quickJs {
    val helloModuleCode = """
        export function greeting() {
            return "Hi from the hello module!";
        }
    """.trimIndent()
    addModule(name = "hello", code = helloModuleCode)
    // OR
    val bytecode = compile(
        code = helloModuleCode,
        filename = "hello",
        asModule = true,
    )
    addModule(bytecode)
    // ...
}
```

When evaluating ES module code, no return values will be captured, you may need a function binding to receive the result.

```kotlin
quickJs {
    // ...
    var result: Any? = null
    function("returns") { result = it.first() }

    evaluate<Any?>(
        """
            import * as hello from "hello";
            // Pass the script result here
            returns(hello.greeting());
        """.trimIndent(),
        asModule = true,
    )
    assertEquals("Hi from the hello module!", result)
}
```

### Alias

Want shorter DSL names?

```kotlin
quickJs {
    def("console") {
        prop("level") {
            getter { "DEBUG" }
        }

        func("log") { }
    }

    func("fetch") { "Hello" }

    asyncFunc("delay") { delay(1000) }

    eval<Any?>("fetch()")
    eval<Any?>(compile(code = "fetch()"))
}
```

Use the DSL aliases then!

```diff
-import com.dokar.quickjs.binding.define
-import com.dokar.quickjs.binding.function
-import com.dokar.quickjs.binding.asyncFunction
-import com.dokar.quickjs.evaluate
+import com.dokar.quickjs.alias.def
+import com.dokar.quickjs.alias.func
+import com.dokar.quickjs.alias.asyncFunc
+import com.dokar.quickjs.alias.eval
+import com.dokar.quickjs.alias.prop
```

# Type mappings

Some built-in types are mapped automatically between C and Kotlin, this table shows how they are
mapped.

| JavaScript type | Kotlin type                           |
|-----------------|---------------------------------------|
| null            | null                                  |
| undefined       | null (1)                              |
| boolean         | Boolean                               |
| Number          | Long/Int/Short/Byte, Double/Float (2) |
| string          | String                                |
| Array           | List<Any?>                            |
| Set             | Set<Any?>                             |
| Map             | Map<Any?, Any?>                       |
| Error           | Error                                 |
| object          | JsObject                              |
| Int8Array       | ByteArray                             |
| UInt8Array      | UByteArray                            |

(1) A Kotlin `Unit` will be mapped to a JavaScript `undefined`, conversely, JavaScript `undefined` won't be mapped to Kotlin `Unit`. 

(2) When converting a JavaScript `Number` to Kotlin `Int`, `Short`, `Byte` or `Float` and the value is out of range, it will throw

### Custom types

`TypeConverter`s are used to support mapping non-built-in types. You can implement your own type
converters:

```kotlin
data class FetchParams(val url: String, val method: String)

// interface JsObjectConverter<T : Any?> : TypeConverter<JsObject, T>
object FetchParamsConverter : JsObjectConverter<FetchParams> {
    override val targetType: KType = typeOf<FetchParams>()

    override fun convertToTarget(value: JsObject): FetchParams = FetchParams(
        url = value["url"] as String,
        method = value["method"] as String,
    )

    override fun convertToSource(value: FetchParams): JsObject =
        mapOf("url" to value.url, "method" to value.method).toJsObject()
}

quickJs {
    addTypeConverters(FetchParamsConverter)

    asyncFunction<FetchParams, String>("fetch") {
        // Use the typed fetch params
        val (url, method) = it
        TODO()
    }

    val result = evaluate<String>(
       """await fetch({ url: "https://example.com", method: "GET" })"""
    )
}
```

You can also use the converter from `quickjs-kt-converter-ktxserialization`
and `quickjs-kt-convereter-moshi` (JVM only).

1. Add the dependency
    ```kotlin
    implementation("io.github.dokar3:quickjs-kt-converter-ktxserialization:<VERSION>")
    // Or use the moshi converter
    implementation("io.github.dokar3:quickjs-kt-converter-moshi:<VERSION>")
    ```

2. Add the type converters of your classes
    ```kotlin
    import com.dokar.quickjs.conveter.SerializableConverter
    // For moshi
    import com.dokar.quickjs.conveter.JsonClassConverter

    @kotlinx.serialization.Serializable
    // For moshi
    @com.squareup.moshi.JsonClass(generateAdapter = true)
    data class FetchParams(val url: String, val method: String)

    quickJs {
        addTypeConverters(SerializableConverter<FetchParams>())
        // For moshi
        addTypeConverters(JsonClassConverter<FetchParams>())

        asyncFunction<FetchParams, String>("fetch") {
            // Use the typed fetch params
            val (url, method) = it
            TODO()
        }
   
        val result = evaluate<String>(
            """await fetch({ url: "https://example.com", method: "GET" })"""
        )
   }
   ```

> [!NOTE]
> Functions with generic <T, R> require exactly 1 parameter on the JS side, it will throw if no parameter is passed or multiple parameters are passed.

# Error handling

Most of functions may throw:

- `IllegalStateException`, if some function was called after calling `close`

`evaluate()` and `compile()` may throw:

- `QuickJsException`, if a JavaScript error occurred or failed to map a type between JavaScript and Kotlin
- Other exceptions, if they were occurred in the Kotlin binding

If you find other suspicious errors, please feel free to open an issue to report

# Samples

- **[js-eval](./samples/js-eval)**: A GUI Compose Multiplatform app to evaluate JS, some minimal JS snippets are builtin
- **[openai](./samples/openai)**: Like `js-eval` but it has some Web API polyfills to run the bundled [openai-node](https://github.com/openai/openai-node)
- **[repl](./samples/repl)**: Simple Multiplatform REPL command line tool using [clikt](https://github.com/ajalt/clikt)

# Development

## Prerequisites

### Common Requirements
- JDK 11 or higher
- Gradle (provided via gradlew)
- CMake 3.10+
- Ninja Build System
- Git

### macOS Specific
```bash
# Install Zig compiler (for cross-compiling)
brew install zig

# Install CMake and Ninja (if not already installed)
brew install cmake ninja
```

### Linux Specific
```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y cmake ninja-build

# Install Zig
# Download from https://ziglang.org/download/
```

### Android Development (Optional)
If you need to build for Android, install Android SDK and NDK.

## Building and Publishing to Maven Local

### Option 1: Using the Publish Script (Recommended)

The script supports different modes for local development and CI/CD environments:

```bash
# Local development (detailed output)
./publish-local.sh

# CI mode (minimal output)
./publish-local.sh --quiet
# or
./publish-local.sh --ci
# or
./publish-local.sh -q

# Skip clean step (faster rebuild)
./publish-local.sh --skip-clean

# Show help
./publish-local.sh --help
```

**Script features:**
- ✅ Auto-detects OS and architecture (macOS/Linux, x64/ARM64)
- ✅ Auto-finds and configures JAVA_HOME
- ✅ Supports verbose and quiet modes
- ✅ Auto-backs up local.properties (in verbose mode)
- ✅ Friendly error messages and progress indicators
- ✅ Unified script with parameter control

### Option 2: Manual Gradle Commands

```bash
# 1. Set execution permissions
chmod +x gradlew
chmod +x quickjs/native/cmake/*.sh

# 2. Configure local.properties (based on your platform)
# macOS ARM64
echo "JAVA_HOME_MACOS_AARCH64=/path/to/your/java/home" >> local.properties

# macOS x64
echo "JAVA_HOME_MACOS_X64=/path/to/your/java/home" >> local.properties

# Linux x64
echo "JAVA_HOME_LINUX_X64=/path/to/your/java/home" >> local.properties

# Linux ARM64
echo "JAVA_HOME_LINUX_AARCH64=/path/to/your/java/home" >> local.properties

# 3. Build and publish
./gradlew clean build publishToMavenLocal
```

## Published Modules

After successful publishing to `~/.m2/repository`:

1. **quickjs** - Core QuickJS engine (supports Android, iOS, macOS, Linux, Windows)
2. **quickjs-converter-ktxserialization** - Kotlinx Serialization converter (multiplatform)
3. **quickjs-converter-moshi** - Moshi JSON converter (Android, JVM)

## Using in Your Project

Add to your `build.gradle.kts`:

```kotlin
repositories {
    mavenLocal()  // Add local Maven repository
    mavenCentral()
    // ... other repositories
}

dependencies {
    implementation("io.github.qdsfdhvh:quickjs-kt:<version>")
    
    // Optional: Add converters
    implementation("io.github.qdsfdhvh:quickjs-converter-ktxserialization:<version>")
    // or
    implementation("io.github.qdsfdhvh:quickjs-converter-moshi:<version>")
}
```

## Troubleshooting

### Issue 1: `zig` command not found
```bash
# macOS
brew install zig

# Linux
# Download from https://ziglang.org/download/
```

### Issue 2: Permission denied errors
```bash
chmod +x gradlew
chmod +x quickjs/native/cmake/*.sh
```

### Issue 3: JAVA_HOME not set
```bash
# macOS
export JAVA_HOME=$(/usr/libexec/java_home)

# Linux
export JAVA_HOME=/usr/lib/jvm/java-11-openjdk-amd64
# Or find your Java installation path
```

### Issue 4: CMake errors
Ensure CMake 3.10+ and Ninja are installed:
```bash
cmake --version
ninja --version
```

## CI/CD Integration

### GitHub Actions Example

```yaml
name: Build and Publish

on: [push]

jobs:
  build:
    runs-on: ${{ matrix.os }}
    strategy:
      matrix:
        os: [macos-latest, ubuntu-latest]
    
    steps:
    - uses: actions/checkout@v3
    
    - name: Set up JDK
      uses: actions/setup-java@v3
      with:
        java-version: '17'
        distribution: 'temurin'
    
    - name: Install Zig (macOS)
      if: runner.os == 'macOS'
      run: brew install zig
    
    - name: Install Zig (Linux)
      if: runner.os == 'Linux'
      run: |
        wget https://ziglang.org/download/0.11.0/zig-linux-x86_64-0.11.0.tar.xz
        tar -xf zig-linux-x86_64-0.11.0.tar.xz
        echo "$PWD/zig-linux-x86_64-0.11.0" >> $GITHUB_PATH
    
    - name: Publish to Maven Local
      run: ./publish-local.sh --ci
```

## Version History

| Version | QuickJS Version | Date | Changes |
|---------|-----------------|------|---------|
| 1.0.0-alpha14 | 2025-04-26 | 2025-11-26 | Update QuickJS to latest, add Android 64KB page support |
| 1.0.0-alpha13 | 2024-02-14 | 2024-xx-xx | Previous version |

# License

```
Copyright 2024 dokar3

Licensed under the Apache License, Version 2.0 (the "License");
you may not use this file except in compliance with the License.
You may obtain a copy of the License at

    http://www.apache.org/licenses/LICENSE-2.0

Unless required by applicable law or agreed to in writing, software
distributed under the License is distributed on an "AS IS" BASIS,
WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
See the License for the specific language governing permissions and
limitations under the License.
```

