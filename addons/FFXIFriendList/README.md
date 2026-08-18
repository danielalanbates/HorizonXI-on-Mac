
<p align="center">
  <a href="https://discord.gg/JXsx7zf3Dx">
    <img src="assets/discord_banner.png" alt="Join the FFXI Friend List Discord">
  </a>
</p>

## Data Privacy & Terms of Service

**IMPORTANT**: This addon requires a remote server to function. By using it, you agree to the following terms. This addon is community-developed and is not affiliated with or endorsed by Square Enix or any private server operators. The service processes only in-game character data required to provide friend list functionality, including character name and realm, friend relationships and requests, presence and heartbeat timestamps used to compute online status and last seen, character metadata such as job, nation, rank, and zone when sharing is enabled, account associations, and server-synced preferences. Friend notes are stored locally and never transmitted to the server. No real-world personal information such as name, email, or address is collected. Data is used only to operate the service, is not sold, tracked, advertised, or shared with third parties, raw IP addresses are not stored by the application though infrastructure providers may process them, server-side data may be backed up for reliability, and data is retained while your account remains active with account deletion available upon request. The service is provided "as-is" with no uptime guarantees, access may be revoked for abuse or operational reasons, you are responsible for protecting your API key, and use of the addon and service is at your own risk. Continued use constitutes acceptance of these terms, which may change over time.

### Donations & Monetization

No donations, payments, subscriptions, or other financial contributions are accepted or solicited for this addon or its associated service. This project is non-commercial and provided purely as a community service.

# FFXIFriendList

A comprehensive friend list management addon for FFXI private servers using the Ashita v4 framework. This addon provides real-time friend status tracking, account-based character linking, notes (local), and more through a modern ImGui interface.

## Features

### Core Friend Management
- **Friend List Display**: View all your friends with real-time online/offline status (server-computed)
- **Friend Requests**: Send, accept, reject, or cancel pending friend requests
- **Add Friends**: Easily add new friends via the UI or `/befriend` command
- **Block List**: Block players to prevent friend requests and remove existing friendships
- **Toast Notifications**: Get notified when friends come online, go offline, or send friend requests
- **Notification Control**: Enable/disable specific notification types and mute individual friends

### Friend Information
- **Job Information**: View friends' current job, subjob, and levels (when sharing enabled or not anon)
- **Rank Display**: See friends' nation rank (when sharing enabled)
- **Nation Information**: Display which nation friends belong to (when sharing enabled)
- **Zone/Location**: Track which zone friends are currently in (when sharing enabled)
- **Last Seen**: See when friends were last online
- **Linked Characters**: See all characters linked to a friend's account (server-provided)

### Notes & Tags System
- **Local Notes**: Notes are stored locally on your device
- **Note Editor**: Rich text editor for friend notes with character count
- **Per-Account**: Notes are stored per-account and shared across all characters on the same account
- **Tag Organization**: Create custom tags to organize friends into groups (e.g., "Favorite", "Linkshell", "Crafters")
- **Tag Filtering**: Filter friend list by tags with collapsible tag sections
- **Pending Tags**: Tags automatically apply when friend requests are accepted

### Account & Character Management
- **Automatic Account Association**: Server automatically associates characters to accounts
- **Character Switching**: Server handles character switching and account merging automatically
- **Multi-Character Support**: Manage multiple characters under a single account
- **Alt Awareness**: See all linked characters for friends (server-provided)
- **Identity Recovery**: If API key is lost, server can recover identity via character name + realm
- **Realm Detection**: Automatic detection and selection of your server/realm

### Privacy & Presence
- **Presence Status**: Set your status as Online, Away, or Invisible
- **Presence Selector**: Choose your online status before logging in
- **Share Online Status**: Control whether you appear online to friends
- **Share Character Data**: Control sharing job/nation/rank information
- **Share Location**: Control sharing your current zone/location
- **Share Job When Anonymous**: Option to show job even in anonymous mode
- **Anonymous Mode**: Hide all character data while appearing online
- **Preferences Sync**: Preferences are synced to the server across all characters (per-account)
- **Immediate Apply**: Preference changes apply immediately (no save button needed)

### Notifications & Sounds
- **Toast Notifications**: Customizable notifications for friend events
- **Notification Types**: Friend online, friend offline, friend requests, request accepted/declined
- **Sound Alerts**: Custom sound effects for different notification types
- **Notification Duration**: Customize how long toast notifications are displayed
- **Notification Positioning**: Drag notifications to reposition with SHIFT key
- **Stack Direction**: Stack notifications from top-down or bottom-up
- **Progress Bar**: Optional progress bar showing time remaining on notifications
- **Test Notifications**: Preview notifications with adjustable settings
- **Per-Friend Muting**: Mute notifications for specific friends
- **Custom Sounds**: Override default sounds with your own .wav files

### Display & Customization
- **Themes**: 5 built-in themes plus support for custom themes
  - Warm Brown
  - Modern Dark
  - Green Nature
  - Purple Mystic
  - Ashita
- **Custom Themes**: Create and save your own color schemes
- **Transparency Controls**: Adjust window and text transparency
- **Font Scaling**: Customize font size for better readability
- **Column Visibility**: Show/hide columns (Job, Rank, Nation, Zone, Last Seen, Friended As)
- **Column Resizing**: Resize table columns to your preference
- **Color Customization**: Fine-tune colors for all UI elements (RGBA)
- **Tab Icons**: Optional icon display for tabs with customizable colors
- **Custom Assets**: Override sounds and icons with your own files
- **Window Locking**: Lock windows to prevent accidental movement or closing

### Quick Online View
- **Condensed Window**: A minimal, name-only view of online friends
- **Hover Details**: Hold mouse over a friend to see full details
- **SHIFT Override**: Hold SHIFT while hovering to show all fields regardless of settings
- **Tag Grouping**: Shows friends grouped by tags in Quick Online view
- **Customizable Columns**: Choose which columns to display in Quick Online window

### Input & Controls
- **Keyboard Shortcuts**: Custom close key binding support
- **Controller Support**: Xbox, PlayStation, Nintendo Switch Pro, and Stadia controller support
- **Context Menus**: Right-click friends for quick actions (edit note, change tag, mute, block, remove)
- **Filter/Search**: Real-time search to filter friends by name
- **Sorting**: Sort friends by any column (name, job, zone, status, last seen)

## Commands

### Main Commands

- **`/fl`** or **`/fl show`** - Toggle the friend list window (show/hide)
- **`/fl help`** or **`/fl h`** - Display help information
- **`/befriend <name>`** - Send a friend request to the specified player

## Installation

### Prerequisites

1. **Ashita v4**: This addon requires Ashita v4 framework

### Automatic Installation (Recommended)

1. Download `Install-FFXIFriendList.bat` from [GitHub Releases](https://github.com/Tanyrus/FFXIFriendList/releases) (inside the ZIP or as a separate file)
2. Double-click `Install-FFXIFriendList.bat`
3. The installer will:
   - Automatically detect your Ashita installation (or prompt you to select the folder)
   - Download and install the latest version from GitHub
   - Add the addon to your `scripts/default.txt` to load automatically
   - Preserve your existing configuration and settings

**Note**: When the folder browser appears, select your Ashita root directory - this is the folder that **CONTAINS** the `addons`, `scripts`, and `config` folders. For Horizon XI, this is typically the `Game` folder.

### Manual Installation

1. Download the latest release (`FFXIFriendList-x.x.x.zip`)
2. Extract the `FFXIFriendList` folder to your Ashita addons directory:
   - `<Ashita Root>/addons/FFXIFriendList/`
3. Load the addon in-game with `/addon load FFXIFriendList`
4. (Optional) Add `/addon load ffxifriendlist` to your `scripts/default.txt` to load automatically

## Configuration

### Configuration Files

Configuration files are stored in:
- `config/addons/FFXIFriendList/`

### Custom Assets

You can override default sounds and icons by placing custom files in the config folder:
- `config/addons/FFXIFriendList/sounds/` - Custom notification sounds (.wav)
- `config/addons/FFXIFriendList/images/` - Custom icons (.png)

See the README.txt in the config folder for available file names.

### Realm Detection

**To set your realm**: The addon will request your server on first load. If your server is not listed, submit an issue on GitHub and it will be added.

### Local Data

Local-only data (not synced to server):
- Local notes
- Tags and tag assignments
- Theme preferences
- Notification duration and position
- Window positions and sizes
- UI customization (column widths, visibility, transparency, fonts)
- Sound preferences
- Controller bindings
- Custom close key

## Usage Examples

### Adding a Friend

1. Open the friend list window (`/fl`)
2. Click "Add New Friend" button
3. Enter the friend's character name
4. Press Enter or click "Add Friend"
5. A friend request will be sent

Alternatively, use the command:
```
/befriend PlayerName
```

### Adding a Note

1. Open the friend list window (`/fl`)
2. Right-click on a friend and select "Edit Note" (or just left-click their row)
3. Enter your note in the editor
4. Click "Save"

**Note Storage**:
- Notes are stored locally on your device by default (per-account)
- Notes are shared across all characters on the same account

### Using Tags

1. Open the friend list window
2. Right-click on a friend and select "Edit Tag"
3. Choose an existing tag or create a new one
4. Tags group friends into collapsible sections
5. Manage all tags in the Settings tab

**Tag Features**:
- Tags are stored locally (not synced to server)
- Pending tags automatically apply when friend requests are accepted
- Collapse/expand tag sections to organize your view
- "Favorite" tag is created by default

### Blocking a Player

1. Right-click on a friend
2. Select "Block & Remove"
3. Confirm the action
4. The player will be removed from your friend list and blocked

**Block Effects**:
- Blocked players cannot send you friend requests
- Existing friendships are automatically removed
- Block list is server-synced across all characters
- Manage blocked players in the Settings tab

### Switching Characters

1. Log out and log in with a different character
2. Addon automatically detects character change and reconnects
3. Server handles account association automatically
4. Friend list and server preferences are shared across all characters
5. Local data (notes, tags, theme) persists per-account

**Note**: The server automatically merges accounts if you switch to a character that belongs to a different account or creates character associations as needed.

## Troubleshooting

### Addon Not Loading

- **Check Ashita version**: Ensure you're using Ashita v4
- **Check addon location**: Verify `FFXIFriendList.lua` is in the `addons/FFXIFriendList` directory
- **Check Ashita logs**: Look for error messages in Ashita's log files
- **Reload addon**: Try `/addon reload FFXIFriendList`

## Support

### Reporting Issues

When reporting issues, please include:
- Addon version (displayed in the main window)
- Ashita version
- Server/Realm name
- Steps to reproduce the issue
- Screenshots (if applicable)
- Any error messages from Ashita logs

## License

This project is licensed under the GNU General Public License v3 (GPLv3). You can find the full license text [here](LICENSE).

**Key aspects of GPLv3:**
- **Free Software:** Grants users the freedom to run, study, modify, and share the software.
- **Strong Copyleft:** Any software derived from or linked with this code must also be released under GPLv3.
- **Patent Protection:** Explicitly protects users from patent claims by contributors.

## Acknowledgments

- Uses the Ashita v4 addon framework
- Powered by ImGui for the user interface
- Uses [nonBlockingRequests](https://github.com/loonsies/nonBlockingRequests) for async networking

