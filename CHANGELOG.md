# What changed

Newest first. Written for players: what you will notice.

## 3.3.0 (2026-11-04) - ready for friends

**Fixed**
- Family-friendly really hides games now. It switched off the wrong RetroBat setting, so RetroBat kept showing every hidden game. Turn it on and press PLAY.
- Your three favourite games come back when you log in on another computer, and are no longer wiped online when the wizard closes. A favourite that computer does not have is still kept.
- Play-together invites arrive. Every invite, and every Join or No answer, was being thrown away by the other wizard because of how its time was written. A friend still on 3.2 can invite you too.
- Every setup signs in to ScreenScraper with the shared login by itself the next time it presses PLAY, not only brand-new ones. A setup that already has a login keeps its own.
- The online library shows in a couple of seconds. It used to wait for every box art picture to download first, one at a time (about a minute every week, and longer on a new setup); now the list comes straight away and the pictures fill in behind it, eight at a time.

**New**
- Play time follows you. Your time on every game is kept online, so most played and recently played on your profile count every computer you play on, including games that computer does not have.
- Box art for games with none: a game with no pictures at all gets its box art by itself, from the free libretro thumbnails, in time for the next PLAY. Games that already have any picture are never touched, and RetroBat's own scraper still works as before. Switch it off on Features.
- Steam on this computer is on the Games tab now, with the other places games come from.
- The installer's mage stands at the end of each bar while it fills, instead of riding it.

**Games tab**
- Downloads show real progress that moves smoothly, with speed and time left. The banner at the top fills for real while something downloads or uploads.
- Less freezing: starting, finishing or reordering a download only redraws that game and the download line, and a console's games are only built when you first open it.

**Tidier pages**
- Help is just Help now: the website, what's new, Send feedback and updates.
- How this setup works is rewritten for how the wizard works today (with a part for coding nerds), and opens in its own window from the What the Wizard is box.
- Set this computer up moved to Settings, This computer. Add a shortcut to a game moved to Features. Make this drive R: moved next to the other several-computers settings. Rename the button is gone from the window (Buttons\Rename The Wizard Button.bat still does it).

**Admins**
- The ScreenScraper card says whether the login really reached the friends store, instead of saying it was shared when it was only saved on this drive.
- Phone pings say what kind of report it is and who sent it.

**Taken out**
- Separate saves per person. It was never switched on, and everybody shares the drive's saves.

## Admin tools refresh (2026-10-26) - no player update

Only the Admin tab's files changed, so the wizard stays 3.2.0 and players are offered nothing.
- Publish games: folder games now find their name, players, description, box art and video preview from RetroBat, like every other game.
- A game is never listed twice: publishing a game again (even under a new name) replaces its old entry, picture, video and file, and every publish ends with a tidy that clears any duplicate or stray upload.
- Publishing the same folder game again no longer re-uploads it.
- The game picker has a console search box and a Select all / Clear all button.

## 3.2.0 (2026-10-31) - the tidy house

**The wizard's folder**
- The wizard's folder is now RetroBat\_Wizard, sorted into eight rooms: Program, Settings, People, Backups, Buttons, Apps, Owner and Cache. START HERE.txt explains each one.
- The move happens by itself the first time the wizard opens after the update. Every button, desktop icon and shortcut is pointed at the new place, and nothing is deleted.

**Setting up**
- The installer is a single file that runs straight from the zip, and finishes a setup that was cut off part way.
- A new setup starts with the shared ScreenScraper login already filled in (admins: press Share my ScreenScraper login once on the Admin page).
- Breath of the Wild gets Vulkan and background shader building on new setups; the Set up Breath of the Wild button adds them on older ones.
- Setup and help no longer assume RetroBat is on an external drive.

**Online library**
- Add as many games as you like: they wait in a line and two download at a time. Move one up or take it out of the line.
- Games made of several files (.cue with .bin tracks, .gdi, .m3u multi-disc) and whole-folder games (PS3, Wii U) can be shared now. They need wizard 3.2 to download.
- Admins: add more games to the upload queue while it is already going, and A folder game publishes a game that is a folder.

**Other**
- Health page: Look for missing games finds games RetroBat is not showing (wrong console folder, a file type that console does not read, hidden) and fixes them where it is safe.
- Family-friendly lists: search the games on this setup instead of typing the name.
- The theme picker is back in the website's settings.

## 3.1.0 (2026-10-25) - the polish round

**Setting up**
- The installer finds RetroBat by itself, names each step as it goes, and closes when it is done.
- Every setup question has a Back button.
- Setup asks where RetroBat lives: on a drive you carry about, or on this computer. On this computer, the drive-letter and several-computers parts stay out of the way.
- A new setup starts with good RetroBat settings: no menu music, only the All games, 2-player and 4-player collections, grid views, and box art found by itself.

**Playing**
- Flash, point-and-click and browser games say first how the controller works in them, with Continue to the game, Back, or X to change the buttons right there.
- Which key each controller button presses in a keyboard game: a default for everybody, and each person can have their own. Every keyboard game in one list: Controllers, Keyboard game buttons.
- Family-friendly (Features page): hides M-rated games from RetroBat, the online library and Jump in. Add your own games or let one through on Settings, This setup.
- Wii games that also work with a normal controller ask first; a controller skips the Wii Menu.
- The couch mouse pop-up has new pictures, says Controller, and sits in the corner out of the way.
- Bring your own Wii Menu: Settings, This setup, Wii Menu.
- A Controllers window: every controller, what it is pressing, and a Buzz button that shakes it so you can find it.

**The wizard**
- Its own title bar that blends into the window, with gold minimise, full screen and close buttons that glow (red for close).
- New page pictures: a chest that tries to open, two friends who shake hands, a spinning star globe, crisper gears, a key that spins, and rune switches that light up.
- Move around the wizard while it works. A bar at the top shows everything that is going, with how far along it is. Closing or PLAY asks first; uploads and downloads can carry on while you play, and the wizard closes itself when they finish.
- Forgot your password? Ask from the login box, and an admin can reset it.
- New pictures for profiles and machines: Wii Remote, Wii U GamePad, Xbox, PlayStation and more.
- Zoom and move your own profile picture.
- Play time and favourite stars follow the person who is playing, not the drive.
- Pick an accent colour (gold, blue, violet or rose) under Theme.
- Saves: Export saves packs every save into one file; Import saves brings them back (with a safety copy first). Installed game updates and DLC are left out, so it is quick.
- The online library is grouped by company, each game opens for a closer look, there is a Request a game button, and downloads show how far they have got.
- Stable or Dev: the page says which one this setup runs, and one press switches.

**For admins**
- The admin tools are their own download now: ordinary setups never get them, and an admin gets them with one button on the Admin page.
- Uploads try again by themselves when the connection drops, show speed and time left, and are checked against the file on your drive.
- Rearrange or cross off games before and during publishing.
- Share a ScreenScraper login with new setups.

## 3.0.0 (2026-10-14) - the new look

**The wizard**
- A whole new look: a home screen with PLAY and big tiles, a side bar on every other page, and one Settings page for this computer, this drive, and health checks.
- New name and fire: "THE RETROBAT WIZARD", with flames that rise.
- New pixel icons that move: a chest for Games, a crystal ball for Social, a mirror for Play online, potions for Saves, gold gears for Settings.
- Light, dark, or follow Windows, for every window the drive opens. Pick it from Theme in the side bar.
- Gold and charcoal text boxes, buttons and floating scroll bars; a glowing amber highlight when you use a controller.
- Grows with the window, so full screen is easy to read from the couch.
- A ribbon along the bottom: drive health, who is playing, this computer, and the version, each one clickable.
- Social: one pencil edits your whole profile (picture, name, status, a short line).
- Help: a new page with the website, what changed, and one place to send feedback.

**Games**
- Wii U: every game opens on a controller screen. Party games ask Wii Remotes or Pro Controller; GamePad games say what they need.
- Wii U games that use the GamePad screen: push in the left stick for a mouse on the right stick (push it in to tap).
- Wii U games now open in front of RetroBat, not behind it.
- Flash and browser games can have their own keyboard layout on the controller.
- Browser games open full screen; app games (like New Club Penguin) download once and live on the drive.
- Player counts for every game, including handhelds and Steam.
- Steam: a clearer setup that checks Steam really sees the drive.
- The online library takes games bigger than 2 GB (they go up in pieces and come back as one).

**Fixes**
- A save with a very long file name (Paper Mario: Color Splash) is now backed up.
- The rename button also renames the icons on the computer.

**For admins**
- The admin tools are their own download now: ordinary setups never get them, and an admin gets them with one button on the Admin page.
- The Admin page refreshes itself when opened.
