# How to Install DecapPub on Your iPhone

You have three main options for installing your app. Here's what you need to know:

---

## Option 1: Direct Install via Xcode (Easiest for Development)

**Best for**: Testing while developing, no setup required

### Requirements
- Mac with Xcode installed
- iPhone connected via USB or Wi-Fi
- Free Apple ID (no paid developer account needed)

### Steps

1. **Connect Your iPhone**
   - Plug in via USB, or
   - Enable Wi-Fi sync: Settings → General → iPhone Storage → Sync with this iPhone over Wi-Fi

2. **Trust Your Computer**
   - When prompted on iPhone, tap "Trust This Computer"

3. **Select Your Device in Xcode**
   - Top toolbar: Click the device selector (currently shows simulator)
   - Choose your iPhone from the list

4. **Configure Signing (First Time Only)**
   - In Xcode, select your project in the navigator
   - Select "DecapPub" target
   - Go to "Signing & Capabilities" tab
   - Check "Automatically manage signing"
   - Select your Apple ID from "Team" dropdown
   - If no team appears, click "Add Account" and sign in with your Apple ID

5. **Build and Run**
   - Press `Cmd + R` or click the Play button
   - Wait for build to complete
   - App will install and launch on your iPhone

6. **Trust the Developer Certificate (First Time Only)**
   - On iPhone: Settings → General → VPN & Device Management
   - Tap your Apple ID email
   - Tap "Trust [Your Apple ID]"
   - Confirm

### Limitations
- ⚠️ **App expires after 7 days** with free Apple ID
- Must rebuild and reinstall every week
- Can only have 3 apps installed this way at once
- App is removed if you disconnect iPhone for extended period

---

## Option 2: TestFlight (Best for Beta Testing)

**Best for**: Sharing with friends/testers, longer install duration, professional distribution

### Requirements
- **Paid Apple Developer Program** ($99/year) - **Required for TestFlight**
- Mac with Xcode installed
- App Store Connect account

### Steps

#### Part 1: Enroll in Apple Developer Program

1. Go to [developer.apple.com/programs](https://developer.apple.com/programs)
2. Click "Enroll"
3. Sign in with your Apple ID
4. Pay $99 annual fee
5. Wait for approval (usually 24-48 hours)

#### Part 2: Create App Store Connect Record

1. Go to [appstoreconnect.apple.com](https://appstoreconnect.apple.com)
2. Click "My Apps" → "+" → "New App"
3. Fill in details:
   - **Platform**: iOS
   - **Name**: DecapPub (or your chosen name)
   - **Primary Language**: English
   - **Bundle ID**: Create new → `com.yourname.DecapPub`
   - **SKU**: `decappub-001` (any unique identifier)
   - **User Access**: Full Access

#### Part 3: Configure Xcode

1. Open your project in Xcode
2. Select project → Target → "Signing & Capabilities"
3. Under "Team", select your paid developer account
4. Set "Bundle Identifier" to match App Store Connect (e.g., `com.yourname.DecapPub`)
5. Ensure "Automatically manage signing" is checked

#### Part 4: Archive and Upload

1. **Select Device**: Choose "Any iOS Device (arm64)" from device selector
2. **Archive**: Product → Archive (or `Cmd + Shift + B`)
3. **Wait for Archive**: This takes 2-5 minutes
4. **Organizer Opens**: Shows your archived build
5. **Distribute App**: Click "Distribute App"
6. **Select Method**: Choose "TestFlight & App Store"
7. **Upload**: Follow prompts, click "Upload"
8. **Wait for Processing**: 5-15 minutes for Apple to process

#### Part 5: Add Testers

1. Go to App Store Connect → TestFlight tab
2. Wait for "Processing" to change to "Ready to Submit"
3. Click "Missing Compliance" → Answer questions about encryption:
   - Does your app use encryption? **No** (unless you added custom crypto)
   - Click "Start Internal Testing"
4. **Add Internal Testers**:
   - Click "Internal Testing" → "+"
   - Add yourself (and up to 99 other people on your team)
   - They'll receive email invitations
5. **Or Add External Testers** (for public beta):
   - Requires App Review (1-2 days)
   - Can add up to 10,000 testers
   - Must provide beta app review info

#### Part 6: Install via TestFlight

1. **Install TestFlight App**: Download from App Store on iPhone
2. **Accept Invitation**: Tap link in email or enter code
3. **Install App**: Tap "Install" in TestFlight
4. **App installed**: No expiration, stays until you remove it

### Benefits
✅ App doesn't expire (lasts up to 90 days per build)
✅ Share with up to 10,000 external testers
✅ Professional distribution
✅ Automatic updates when you upload new builds
✅ Crash reports and feedback from testers

### Limitations
- 💰 Requires $99/year Apple Developer membership
- ⏰ Initial setup takes time
- 📝 Some bureaucracy with App Store Connect

---

## Option 3: Ad Hoc Distribution (For Specific Devices)

**Best for**: Installing on 2-5 specific devices without TestFlight

### Requirements
- Paid Apple Developer Program ($99/year)
- Device UDIDs (unique identifiers)

### Steps

1. **Get Device UDID**
   - Connect iPhone to Mac
   - Open Finder → Select iPhone
   - Click on serial number until UDID appears
   - Right-click UDID → Copy

2. **Register Device in Apple Developer Portal**
   - Go to [developer.apple.com/account](https://developer.apple.com/account)
   - Certificates, Identifiers & Profiles → Devices
   - Click "+" → Register device
   - Paste UDID, give it a name

3. **Create Provisioning Profile**
   - Profiles → "+" → Ad Hoc
   - Select your App ID
   - Select your certificate
   - Select registered devices
   - Download profile

4. **Archive and Export in Xcode**
   - Product → Archive
   - Distribute App → Ad Hoc
   - Select devices to include
   - Export

5. **Install on Device**
   - Use Apple Configurator 2, or
   - Drag IPA to Xcode Devices window

### Limitations
- Expires after 1 year
- Must manually add each device UDID
- Awkward installation process

---

## My Recommendation

### For You (Solo Developer)

**Right Now**: Use **Option 1 (Direct Install via Xcode)**
- Free
- Instant
- Good enough for development
- Just rebuild once a week

**Long Term**: Upgrade to **Option 2 (TestFlight)** when:
- You want to share with friends
- Tired of weekly reinstalls
- Ready to publish to App Store eventually

### For Sharing with Others

**TestFlight is the only practical option** for sharing with multiple people.

---

## Quick Start: Install Right Now (Option 1)

Here's what to do in the next 5 minutes:

```bash
# 1. Plug in your iPhone via USB

# 2. In Xcode:
#    - Top toolbar: Click device selector
#    - Choose your iPhone
#    - Cmd + R (or click Play button)

# 3. On iPhone when build completes:
#    Settings → General → VPN & Device Management
#    Tap your email → Trust

# 4. Done! App is installed.
```

---

## Troubleshooting Common Issues

### "Signing for DecapPub requires a development team"
**Solution**: Go to Signing & Capabilities → Select your Apple ID in Team dropdown

### "iPhone is locked"
**Solution**: Unlock your iPhone and try again

### "Untrusted Developer"
**Solution**: Settings → General → VPN & Device Management → Trust your certificate

### "This app requires iOS 26.0 or later"
**Solution**: Your code requires iOS 26. Change this in two places:
1. `DecapPubApp.swift` - change `#available(iOS 26.0, *)` to lower version
2. Xcode project settings → Deployment Target → set to your iOS version

### "The app could not be installed"
**Solution**: Delete old version of app from iPhone first, then rebuild

---

## Cost Comparison

| Method | Cost | Duration | Max Testers |
|--------|------|----------|-------------|
| Direct Install | Free | 7 days | Just you |
| TestFlight | $99/year | 90 days/build | 10,000 |
| Ad Hoc | $99/year | 1 year | 100 devices |

---

## Next Steps After Installation

Once installed, you'll need to configure:

1. **GitHub Token**: Settings → GitHub Token
   - Generate at github.com/settings/tokens
   - Needs repo access

2. **Site Settings**: Settings → Configure your site details
   - Site name, endpoint, repo, branch

3. **Photo Access**: Grant photo library permission when prompted

---

## FAQ

**Q: Can I install on someone else's iPhone?**
A: Only with TestFlight ($99/year) or if they're near you and you use Xcode direct install.

**Q: Will my app stay installed forever?**
A: 
- Direct install: 7 days, then expires
- TestFlight: 90 days per build, unlimited renewals
- Ad Hoc: 1 year

**Q: Can I publish to the App Store?**
A: Yes! After TestFlight setup, you can submit for App Store review. Same $99/year account.

**Q: Is the $99 worth it?**
A: If you're serious about using this app long-term or sharing it, yes. Otherwise, stick with free direct install.

**Q: Can I install without a Mac?**
A: No, you need Xcode on a Mac to build iOS apps. (Cloud build services exist but are complicated.)

---

## What I Recommend You Do Right Now

1. **Try Option 1 first** (Direct Install via Xcode) - it's free and takes 2 minutes
2. If you love the app and use it regularly, **upgrade to paid Developer Program**
3. Set up **TestFlight** for convenient updates and sharing

The free option is perfectly fine for personal use! The weekly reinstall is a minor inconvenience but saves you $99.

---

Need help with any step? Let me know!
