# Apple M1 Minecraft Launcher

Download and run Minecraft without the Launcher.

## Instructions

This package does not have a visual interface and must be run from the command line. In the future I plan on releasing a version with an interface, however there are technical challenges with this that are not worth the complexity at this time.

1. Install [Homebrew](https://brew.sh) and run `brew install ezfe/tap/minecraft-jar-command`
2. Run `minecraft-jar-command` to launch the game!
3. You will probably need to login first – to do this, run the `login` command:
   ```
   minecraft-jar-command login <your email> <minecraft password> --save-credentials
   ```
   - Your password will not be saved, only your access token - this is how the regular Minecraft launcher logs you in as well
   
Tips:
1. You can change the game version - the latest release version will be used by default. Only some versions are available, you can view the complete list [here](https://f001.backblazeb2.com/file/com-ezekielelin-publicFiles/lwjgl-arm/version_manifest_v2.json).
   ```
   minecraft-jar-command run --version "21w05b-arm64"
   ```
2. To get the latest snapshot version, run it with the `--snapshot` flag:
   ```
   minecraft-jar-command run --snapshot
   ```
3. You can change the game directory and working directory (where the supporting assets are downloaded). Right now, the game directory is set to the default Minecraft directory, and the working directory defaults to a temporary one to prevent interference with the default Minecraft launcher. Refer to `minecraft-jar-command help run` to see these commands.

## Updates

I will do my best to release new Minecraft versions quickly - this will happen automatically, no need to do anything to fetch it.

To receive updates about this script and new versions, click "Watch > Custom > Releases" to get notifications.
