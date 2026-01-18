# Quick Install Guide - DecapPub

## Install Right Now (Free, 2 Minutes)

### What You Need
- ✅ Mac with Xcode
- ✅ iPhone with cable
- ✅ Free Apple ID

### Steps

1. **Plug in iPhone** via USB

2. **In Xcode**:
   - Select your iPhone from device selector (top toolbar)
   - Press `Cmd + R` (or click ▶️ Play button)

3. **On iPhone** (first time only):
   - Settings → General → VPN & Device Management
   - Tap your email → **Trust**

4. **Done!** App is installed.

### Catch
- ⚠️ App expires in **7 days**
- Must rebuild weekly

---

## Upgrade to TestFlight (Recommended Long-Term)

### Cost: $99/year

### Why?
✅ No weekly reinstalls  
✅ Share with friends  
✅ Professional distribution  
✅ Automatic updates  

### How?
1. Enroll: [developer.apple.com/programs](https://developer.apple.com/programs)
2. Create app in App Store Connect
3. Archive in Xcode: `Product → Archive`
4. Upload to TestFlight
5. Install via TestFlight app

**Full instructions**: See `HOW_TO_INSTALL.md`

---

## Troubleshooting

| Problem | Solution |
|---------|----------|
| "No team selected" | Signing & Capabilities → Add your Apple ID |
| "Untrusted Developer" | Settings → General → Device Management → Trust |
| "iPhone is locked" | Unlock and try again |
| "Requires iOS 26" | Change deployment target in project settings |

---

## My Recommendation

**Try free install first!**

If you use the app daily → Upgrade to TestFlight after a week.

If just testing → Stick with free, rebuild weekly.

---

## Next: Configure the App

After install:

1. **Settings → GitHub Token**
   - Generate: github.com/settings/tokens
   - Paste in app

2. **Settings → Site Details**
   - Configure your repo/branch

3. **Grant Photo Access**
   - When prompted
