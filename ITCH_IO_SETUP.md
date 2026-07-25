# Publishing SALTLINE to itch.io

## Quick Summary
SALTLINE is ready to publish. You have two built versions in `builds/`:
- **SALTLINE-Windows.exe** (1.2 GB) — Windows 64-bit, fully standalone
- **SALTLINE-Mac.zip** (0.9 GB) — macOS Intel + Apple Silicon

## Step 1: Create or Access Your itch.io Project

1. Go to **https://itch.io**
2. Click your user icon (top right) → **Dashboard**
3. Click **Create new project** (or edit an existing SALTLINE project)
4. Fill in:
   - **Project name:** `SALTLINE`
   - **Project URL:** `saltline` (or your choice — this becomes the game's itch.io slug)
   - **Classification:** `Game`
   - **Kind of project:** `HTML, Downloadable` (since these are downloadable executables)
   - **Visibility:** Choose `Public` when ready to launch

## Step 2: Set Up Project Details

### Game Information
- **Title:** SALTLINE
- **Short description:** A first-person survival mystery on an abandoned North-Sea oil rig.
- **Description:** (copy from the game's README or expand):
  ```
  SALTLINE is a first-person survival game set on an abandoned North Sea oil rig.
  
  You wake in a survival pod at the waterline. The rig has no power, no crew, and 
  no obvious way off. Restore power, gather supplies, and uncover what happened 
  to the crew while staying alive against the ocean and the things that live in it.
  
  Features:
  • Immersive first-person exploration
  • Survival crafting and resource management  
  • Procedurally populated deep ocean (dynamic fishing rig gameplay)
  • Complete standalone executables — no launcher or installation needed
  • Autosave system with multiple save slots
  
  Requires: Windows 10+ (64-bit) or macOS 11+ (Intel/Apple Silicon)
  ```

### Cover Image
- Use or create a cover image (800×450 minimum, or 1200×675 preferred)
- This is the thumbnail shown on itch.io and in search results

### Screenshots
- Drag 3-5 gameplay screenshots from SALTLINE into the **Screenshots** section
- You can use FacingShot harness to generate fresh ones if needed

### Tags
Add relevant tags for discoverability:
- `survival`
- `first-person`
- `exploration`
- `single-player`
- `atmospheric`
- `mystery`

### Release Status
- Set to **Published** when ready for public release
- Or **In development** if you want to gather feedback first

## Step 3: Upload Game Files

### Option A: Using itch.io's Web Upload (Easiest)
1. In your project page, scroll to **Uploads** section
2. Click **Upload files**
3. For each file:
   - Click **Upload files** → select `SALTLINE-Windows.exe`
   - Leave all defaults
   - Click **Upload**
   - Repeat for `SALTLINE-Mac.zip`

### Option B: Using butler (CLI Tool)
If you prefer command-line, install butler and use:
```bash
butler push /Users/mjspeh/SALTLINE/builds/SALTLINE-Windows.exe your-username/saltline:windows
butler push /Users/mjspeh/SALTLINE/builds/SALTLINE-Mac.zip your-username/saltline:mac
```

## Step 4: Configure Download Settings

For each uploaded file (in **Uploads** section):

**Windows .exe:**
- **Upload name:** Keep default
- **Executable:** Check this box
- **Architecture:** x86_64
- **Supports running on:** Windows (check it)
- **Upload for an external key or tool:** Uncheck

**Mac .zip:**
- **Upload name:** Keep default
- **Executable:** Uncheck (it's a .zip containing an app)
- **Architecture:** universal (macOS Intel + Apple Silicon)
- **Supports running on:** Mac (check it)

## Step 5: Configure Pricing & Availability

1. **Pricing:** 
   - `Free to play` (or set a price if desired)
   
2. **Audience:**
   - **For sale in these countries:** Select based on where you want distribution
   - **Monetization:** Leave default or add to itch.io collections

3. **Access:**
   - **Can be downloaded:** Check this
   - **Can be played in browser:** Uncheck (not applicable for downloadable games)

## Step 6: Additional Settings

- **Communities:** Check relevant communities (gaming, indie games, adventure)
- **Links:** Add your official website/portfolio if you have one
- **Author:** Set to your account name
- **License:** Add license info if applicable

## Step 7: Publish & Share

1. Scroll to the top
2. Make sure **Visibility** is set to `Public`
3. Click **Save & view page** or **Publish**
4. Your game is now live! Share the link:
   ```
   https://your-username.itch.io/saltline
   ```

## Verification Checklist

Before publishing, verify:
- [ ] Game files are named clearly (SALTLINE-Windows.exe, SALTLINE-Mac.zip)
- [ ] Both platforms are listed as supported
- [ ] Description is clear and engaging
- [ ] Cover image and screenshots are uploaded
- [ ] Download links work (test download one file)
- [ ] Windows .exe has 64-bit architecture selected
- [ ] Mac .zip is marked as universal architecture
- [ ] Game is set to Public visibility when ready

## Important Notes

### File Sizes
- The .exe is 1.2 GB — this is normal for Godot games with full assets
- The .zip is 0.9 GB — inform players to expect a large download
- Consider mentioning in the description: "Full game included, no launcher or installation required"

### Updates
To update the game later:
1. Build new versions with Godot
2. Go to your itch.io project
3. Click **Uploads** → Upload new files with the same names
4. itch.io handles versioning automatically

### Metadata Files
The included `README-HOW-TO-PLAY.txt` is already excellent. Consider also uploading it as a downloadable file:
1. In **Uploads**, click **Upload files** again
2. Select `README-HOW-TO-PLAY.txt`
3. Leave it unchecked as executable/platform-specific

## Getting Help
- itch.io Creator Docs: https://itch.io/docs
- Godot Publishing: https://docs.godotengine.org/en/stable/tutorials/export/index.html

---

**Your SALTLINE project is ready to ship!**
