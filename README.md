# Apple M1 Minecraft Launcher

Download and run Minecraft without the Launcher.

## Instructions

This package does not have a visual interface and must be run from the command line. In the future I plan on releasing a version with an interface, however there are technical challenges with this that are not worth the complexity at this time.

1. Download and unarchive the latest release
2. Copy the file to a location in your PATH
   - Recommended location is `/usr/local/bin`, but pick whatever you'd like if you want to run from a different location
3. Run `minecraft-jar-command` to launch the game!
   - You may get an error saying it can't be checked for malicious software – this is okay, click OK and open System Preferences > Security & Privacy and click "Allow Anyways"
   - Try again after allowing it
4. You will probably need to login first – to do this, run the `login` command:
   ```
   minecraft-jar-command login <your email> <minecraft password> --save-credentials
   ```
   - Your password will not be saved, only your access token - this is how the regular Minecraft launcher logs you in as well
   
Tips:
1. You can change the game version - the latest release version will be used by default. Only `1.16.4-arm64`, `1.16.5-arm64`, and `20w51a-arm64` are currently available
   ```
   minecraft-jar-command run --version "20w51a-arm64"
   ```
2. You can change the game directory and working directory (where the supporting assets are downloaded). Right now, the game directory is set to the default Minecraft directory, and the working directory defaults to a temporary one to prevent interference with the default Minecraft launcher. Refer to `minecraft-jar-command help run` to see these commands.

## Updates

I will do my best to release new Minecraft versions quickly - this will happen automatically, no need to do anything to fetch it.

To receive updates about this script and new versions, click "Watch > Custom > Releases" to get notifications.

## Java

You will need to download and install Java 8 for ARM first – You can find the most recent version here:

https://www.azul.com/downloads/zulu-community/?version=java-8-lts&os=macos&architecture=arm-64-bit&package=jdk

To install, copy the folder `zulu-8.jdk` to `/Library/Java/JavaVirtualMachines`. You can test this works by running `java -version` and confirming:

```
openjdk version "1.8.0_275"
OpenJDK Runtime Environment (Zulu 8.50.0.1013-CA-macos-aarch64) (build 1.8.0_275-b01)
OpenJDK 64-Bit Server VM (Zulu 8.50.0.1013-CA-macos-aarch64) (build 25.275-b01, mixed mode)
```
