# DodoShot Development Rules

## Build & Deploy Workflow

**IMPORTANT:** Always reset DodoShot permissions when deploying a new build:

```bash
tccutil reset ScreenCapture com.dodoshot.app
tccutil reset Accessibility com.dodoshot.app
```

This ensures the permission onboarding flow is tested with each new build.

## Architecture Notes

- `Screenshot` stores image as `Data` internally (not `NSImage`) to avoid use-after-free crashes
- Each access to `Screenshot.image` returns a fresh `NSImage` instance
- No need for `deepCopy()` calls - the struct handles image ownership safely
