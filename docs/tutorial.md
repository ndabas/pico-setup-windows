## Installing the tools

The latest release of the installer is available at https://github.com/raspberrypi/pico-setup-windows/releases. Download the file named `pico-setup-windows-<version>-x64-standalone.exe`.

Currently, the installer is only compatible with x64 (x86-64) versions of currently-supported Windows versions.

Run the downloaded file to start the installer. The installer offers an option to choose the install location if you do not want to use the default.

Note that the installer will copy files to two locations:
1. The required tools and executables are copied to Program Files: `C:\Program Files\Raspberry Pi Pico SDK v<version>`. This path can be changed in the installer.
2. Git repositories which are needed for building projects, along with examples and such are copied to a location like `C:\Users\username\Documents\Pico-<version>`.

The repositories are copied to a sub-directory in Documents because the build process needs to write files to those directories.

Note that the installer does not modify any environment variables or the PATH. This is to allow the possibility of using multiple versions of the SDK and tools side-by-side. The installer adds scripts and shortcuts that set up the correct enviroment for a specific version of the installer.

The installer registers a CMake package, `pico-sdk-tools`, so your builds do not need to compile the `pioasm` and `elf2uf2` tools.

## Setting up the enviroment

To configure the appropriate environment variables and PATH needed to build and debug Pico projects, a couple of utility scripts are available. If you're using the Command Prompt (cmd.exe) shell:

```
call "C:\Program Files\Raspberry Pi Pico SDK v1.4.0\pico-env.cmd"
```

To set up the environment in a PowerShell session:

```
. "C:\Program Files\Raspberry Pi Pico SDK v1.4.0\pico-env.ps1"
```

Note that running the PowerShell script might require you to set the [Execution Policy](https://learn.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_execution_policies) first.

## Starting Visual Studio Code

In your Start Menu, look for the _Pico - Visual Studio Code_ shortcut, in the _Raspberry Pi_ folder. The shortcut sets up the needed environment variables and then launches Visual Studio Code.

To launch VS Code from your command line instead, you will need to first set up the environment as described in the previous section, and then start VS Code as usual, for example, `code .`

## Opening the examples

The first time you launch Visual Studio Code using the Start Menu shortcut, it will open the [pico-examples](https://github.com/raspberrypi/pico-examples) repository.

To re-open the examples repository later, you can open the copy installed at `C:\Users\username\Documents\Pico-<version>\pico-examples`.

## Building an example

Visual Studio Code will ask if you want to configure the pico-examples project when it is first opened; click _Yes_ on that prompt to proceed. You will then be prompted to select a kit -- the GCC for Arm compiler installed with the SDK should be detected automatically, so select the _GCC arm-none-eabi_ entry. If the _GCC arm-none-eabi_ entry is not present, select _Unspecified_ to have the SDK auto-detect the compiler.

Note that this functionality is added to VS Code by the CMake Tools extension.

To build one of the examples, click the _CMake_ button on the sidebar. You should be presented with a tree view of the example projects; expand the project you'd like to build, and click the small build icon to the right of the target name to build that specific project.

To build everything instead, click the _Build All Projects_ button at the top of the CMake Project Outline view.

You can change between Debug and Release builds (along with a few more types) by clicking the _CMake: [Debug]_ status bar item at the bottom of the window.

## Debugging an example

The `pico-examples` repository comes with a `.vscode\launch.json` file configured for debugging with Visual Studio Code. You can copy this file into your own projects as well.

To start debugging an example, click the _Run and Debug_ button on the sidebar. The _Pico Debug_ launch configuration should be selected already. To start debugging, click the small 'play' icon at the top of the debug window, or press F5.

The first time you start debugging, you will be prompted to select a target. If you wish to later change the launch target, you can do so using the status bar button with the name of the target.

Assuming that you have a Picoprobe configured and connected to your target device, your selected target should now be built, uploaded, and started. The debugger interface will load, and will pause the execution of the code at the `main()` entry point.

At this point, you can use the usual debugging tools to step, set breakpoints, inspect memory, and so on.

### Wiring up SWD and UART to Picoprobe

Picoprobe wiring is explained in the [Getting started document](https://datasheets.raspberrypi.com/pico/getting-started-with-pico.pdf), _Appendix A: Using Picoprobe_, under the heading _Picoprobe Wiring_.

The Raspberry Pi Pico board used as Picoprobe should be flashed with the latest `picoprobe-cmsis-*` build available from [Picoprobe releases](https://github.com/raspberrypi/picoprobe/releases). The OpenOCD build included with the SDK installer only supports the CMSIS-DAP version of Picoprobe, and not the original release.

### Start OpenOCD

When you start debugging from Visual Studio Code, OpenOCD and gdb are started automatically by the Cortex-Debug extension.

If you wish to start OpenOCD from the command line yourself, you will need to set up the environment as described previously, and then run:

```
openocd -f interface/cmsis-dap.cfg -f target/rp2040.cfg -c "adapter speed 1000"
```

### Open serial monitor in VSCode

The SDK installer adds the _Serial Monitor_ extension to Visual Studio Code. Picoprobe includes a USB-serial bridge as well; assuming that you have wired up the TX and RX pins of the target to Picoprobe as described previously, you should have an option to select _COMn - USB Serial Device (COMn)_ in the _Serial Monitor_ tab in the bottom panel.

The baud rate should be set to the default of 115200 in most cases. Click _Start Monitoring_ to open the serial port.

### Start gdb

If you wish to run gdb from the command line, you can invoke it like this:

```
arm-none-eabi-gdb
```

For example, to load and debug the `hello_serial` example, you might do: (assuming that OpenOCD is already running as described above)

```
cd ~\Documents\Pico-v1.4.0\pico-examples\build\hello_world\serial\
arm-none-eabi-gdb hello_serial.elf # hello_serial.elf is built at SDK install time by pico-setup.cmd
```

Then inside gdb:

```
(gdb) target remote localhost:3333
(gdb) load
(gdb) monitor reset init
(gdb) continue
```

## Creating a new project out of tree

## Uninstalling
