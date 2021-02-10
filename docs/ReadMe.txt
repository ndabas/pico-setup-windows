Pico setup for Windows

Download the latest release from
https://github.com/ndabas/pico-setup-windows/releases

Developer Command Prompt for Pico
Use this shortcut to launch a command prompt configured with the tools and
environment variables needed for Pico development. Note that you should launch
your editor or IDE from this prompt so that it inherits the needed environment
as well.

Visual Studio Code for Pico
Start Visual Studio Code using this link to have the correct environment
variables (like PATH and PICO_SDK_PATH) set for development.

pico-env.cmd
Use this batch file to set up a command prompt with the required environment
variables for Pico development.

pico-setup.cmd
This batch file clones the Pico SDK and related Git repositories, and runs a
few test builds to ensure that everything is working as expected.

design, docs, uf2
These folders contain the Getting Started documents, datasheets, design files,
and UF2 files from the Raspberry Pi Pico getting-started page.

pico-docs.ps1
This PowerShell script downloads all of the latest documents and files from the
Raspberry Pi Pico website.

Pico Project Generator
This is a Python application to help you create new Pico projects.

tools\openocd-picoprobe\openocd.exe
OpenOCD with picoprobe support. Launch from the Developer Command Prompt for
Pico using a command like this:
  openocd -f interface/picoprobe.cfg -f target/rp2040.cfg

tools\zadig.exe
Utility for replacing USB drivers - helpful when using OpenOCD with picoprobe.

Uninstall
Just delete this directory. Any other software that you installed using Pico
setup for Windows will have its own uninstaller.
