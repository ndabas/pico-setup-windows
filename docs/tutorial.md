## Installing the tools

Download [the latest release](https://github.com/raspberrypi/pico-setup-windows/releases/latest/download/pico-setup-windows-x64-standalone.exe) and run it.

## Starting Visual Studio Code

In your Start Menu, look for the _Pico - Visual Studio Code_ shortcut, in the _Raspberry Pi Pico SDK &lt;version&gt;_ folder. The shortcut sets up the needed environment variables and then launches Visual Studio Code.

## Opening the examples

The first time you launch Visual Studio Code using the Start Menu shortcut, it will open the [pico-examples](https://github.com/raspberrypi/pico-examples) repository.

To re-open the examples repository later, you can open the copy installed at `C:\ProgramData\Raspberry Pi\Pico SDK <version>\pico-examples`.

## Building an example

Visual Studio Code will ask if you want to configure the pico-examples project when it is first opened; click _Yes_ on that prompt to proceed. (If you miss the prompt look for the 'bell' icon in the bottom right.) You will then be prompted to select a kit -- select the _Pico ARM GCC - Pico SDK Toolchain with GCC arm-none-eabi_ entry. If the _Pico ARM GCC_ entry is not present, select _Unspecified_ to have the SDK auto-detect the compiler.

To build one of the examples, click the _CMake_ button on the sidebar. You should be presented with a tree view of the example projects; expand the project you'd like to build, and click the small build icon to the right of the target name to build that specific project.

To build everything instead, click the _Build All Projects_ button at the top of the CMake Project Outline view.

## Debugging an example

The `pico-examples` repository comes with `.vscode\*.json` files configured for debugging with Visual Studio Code. You can copy these files into your own projects as well.

To start debugging an example, click the _Run and Debug_ button on the sidebar. The _Pico Debug_ launch configuration should be selected already. To start debugging, click the small 'play' icon at the top of the debug window, or press F5.

The first time you start debugging, you will be prompted to select a target. If you wish to later change the launch target, you can do so using the status bar button with the name of the target.

Assuming that you have a Picoprobe configured and connected to your target device, your selected target should now be built, uploaded, and started. The debugger interface will load, and will pause the execution of the code at the `main()` entry point.

At this point, you can use the usual debugging tools to step, set breakpoints, inspect memory, and so on.

### Wiring up SWD and UART to Picoprobe

Picoprobe wiring is explained in the [Getting started document](https://datasheets.raspberrypi.com/pico/getting-started-with-pico.pdf), _Appendix A: Using Picoprobe_, under the heading _Picoprobe Wiring_.

The Raspberry Pi Pico board used as Picoprobe should be flashed with the latest `picoprobe-cmsis-*` build available from [Picoprobe releases](https://github.com/raspberrypi/picoprobe/releases). The OpenOCD build included with the SDK installer only supports the CMSIS-DAP version of Picoprobe, and not the original release.

### Open serial monitor in VSCode

The SDK installer adds the _Serial Monitor_ extension to Visual Studio Code. Picoprobe includes a USB-serial bridge as well; assuming that you have wired up the TX and RX pins of the target to Picoprobe as described previously, you should have an option to select _COMn - USB Serial Device (COMn)_ in the _Serial Monitor_ tab in the bottom panel.

The baud rate should be set to the default of 115200 in most cases. Click _Start Monitoring_ to open the serial port.

## Command-line usage

To build and debug projects using command-line tools, you can open a terminal window using the _Pico - Developer Command Prompt_ or _Pico - Developer PowerShell_ shortcuts.

### Start OpenOCD and gdb

```powershell
openocd -f interface/cmsis-dap.cfg -f target/rp2040.cfg -c "adapter speed 1000"
```

If you wish to run gdb from the command line, you can invoke it like this:

```powershell
arm-none-eabi-gdb
```

For example, to load and debug the `hello_serial` example, you might do: (assuming that OpenOCD is already running as described above)

```powershell
cd ${env:PICO_EXAMPLES_PATH}\build\hello_world\serial\
arm-none-eabi-gdb hello_serial.elf # hello_serial.elf is built at SDK install time by pico-setup.cmd
```

Then inside gdb:

```
(gdb) target remote localhost:3333
(gdb) load
(gdb) monitor reset init
(gdb) continue
```

## Creating a new project

The commands below are for PowerShell, and will need to be adjusted slightly if you're using Command Prompt instead.

1. Copy pico_sdk_import.cmake from the SDK into your project directory:
   ```powershell
   copy ${env:PICO_SDK_PATH}\external\pico_sdk_import.cmake .
   ```
1. Copy VS Code configuration from the SDK examples into your project directory:
   ```powershell
   copy ${env:PICO_EXAMPLES_PATH}\.vscode .
   ```
1. Setup a `CMakeLists.txt` like:

   ```cmake
   cmake_minimum_required(VERSION 3.13)

   # initialize the SDK based on PICO_SDK_PATH
   # note: this must happen before project()
   include(pico_sdk_import.cmake)

   project(my_project)

   # initialize the Raspberry Pi Pico SDK
   pico_sdk_init()

   # rest of your project

   ```
1. Write your code (see [pico-examples](https://github.com/raspberrypi/pico-examples) or the [Raspberry Pi Pico C/C++ SDK](https://rptl.io/pico-c-sdk) documentation for more information)

   About the simplest you can do is a single source file (e.g. hello_world.c)

   ```c
   #include <stdio.h>
   #include "pico/stdlib.h"

   int main() {
       setup_default_uart();
       printf("Hello, world!\n");
       return 0;
   }
   ```
   And add the following to your `CMakeLists.txt`:

   ```cmake
   add_executable(hello_world
       hello_world.c
   )

   # Add pico_stdlib library which aggregates commonly used features
   target_link_libraries(hello_world pico_stdlib)

   # create map/bin/hex/uf2 file in addition to ELF.
   pico_add_extra_outputs(hello_world)
   ```

   Note this example uses the default UART for _stdout_;
   if you want to use the default USB see the [hello-usb](https://github.com/raspberrypi/pico-examples/tree/master/hello_world/usb) example.


1. Launch VS Code from the _Pico - Visual Studio Code_ shortcut in the Start Menu, and then open your new project folder.

1. Configure the project by running the _CMake: Configure_ command from VS Code's command palette.

1. Build and debug the project as described in previous sections.

## Uninstalling

Open the _Apps and Features_ section in Windows Settings, then select _Raspberry Pi Pico SDK &lt;version&gt;_. Click the _Uninstall_ button and follow the prompts.
