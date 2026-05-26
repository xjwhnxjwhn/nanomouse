# Privacy Policy

**Last Updated: May 26, 2026**

## Overview

NanoMouse is an open-source, cross-platform input method application. We take
privacy seriously, and we keep processing on-device whenever possible. This
policy explains how data is handled under different feature modes.

## Data Processing Principles

- The App uses local processing by default.
- The App does not upload your data to NanoMouse-operated servers for ads or
  analytics.
- If you explicitly enable online ASR or online LLM features, your audio or
  text will be sent to the third-party provider you choose.

## What Data Is Processed

### 1) Keyboard Input Content

- Regular text input is processed locally by default.
- The App does not include third-party ad SDKs.
- The App does not include third-party analytics SDKs.

### 2) Voice Dictation (ASR)

The App supports multiple speech recognition routes. The actual data flow is
based on your settings:

- **Apple Speech**: Processed by Apple system speech capabilities.
- **Whisper (offline)**: Processed on-device with local models.
- **Online ASR**: If you enable online engine mode, audio is sent to the ASR
  provider (or proxy endpoint) you configure.

### 3) AI Text Editing (LLM)

- If you enable AI processing, recognized text is sent to the LLM provider (or
  proxy endpoint) you configure for structuring, rewriting, or translation.
- If this feature is disabled, text is not sent to online LLM processing.

### 4) API Keys and Configuration

- Online ASR/LLM API keys are stored in iOS Keychain (per-provider buckets).
- Model name, Base URL, and feature toggles are stored in local app settings.
- By default, the App does not upload your API keys to NanoMouse-operated
  servers.

### 5) Voice History and Manual Dictionary

- Voice history and manual dictionary entries are stored locally on your device.
- You can clear history and dictionary entries in the app.

### 6) Weather, Location, Photos, Camera, Diary, and Local Network

- **Weather and location**: If you choose current-location weather for the
  keyboard weather indicator, the App requests location permission and uses
  Apple Weather for weather data. Fixed-city weather does not require your
  current location.
- **Photos and camera**: The App requests camera or photo permissions only when
  you take a photo in Byte Paste, import images from Photos, or export images
  to your photo library. The camera and photo library are not accessed when
  those features are not used.
- **Diary protection**: When you view diary content, the App may use Face ID or
  the device passcode for on-device authentication.
- **Local network**: When you upload or manage input schema files through a
  browser, the App uses local network capability so devices on the same network
  can connect to the local service.
- **Product notifications**: The App requests notification permission only when
  you enable product notifications in the app, for product updates, important
  announcements, and service status notices.

## iCloud Sync

If you enable iCloud sync:

- Keyboard configs and dictionary data can sync across your devices via Apple
  iCloud.
- Related data is managed by Apple under its own terms:
  [iCloud Terms](https://www.apple.com/legal/internet-services/icloud/)
- You can disable iCloud sync at any time.

## Full Access Permission

The App requests "Full Access" for keyboard capabilities, including:

- iCloud sync for configs and dictionary
- Haptic feedback
- Reading iOS system text replacement shortcuts

Even with Full Access enabled, the App does not upload your data to
NanoMouse-operated servers for ads or analytics.

## Third-Party Services

When corresponding features are enabled, the App may interact with:

- Apple services and system frameworks (Speech, iCloud/CloudKit, WeatherKit,
  notifications, location, Photos, and camera permission frameworks)
- Online ASR/LLM providers that you select and configure

Data handling by those providers is governed by their own privacy policies.

## Your Controls

You can, at any time:

- Disable online ASR engine
- Disable AI processing (LLM)
- Remove or replace API keys
- Clear voice history
- Manage manual dictionary entries
- Disable iCloud sync
- Disable the weather indicator or use a fixed city instead
- Disable product notifications
- Revoke camera, photo, location, microphone, speech recognition, notification,
  and other permissions in System Settings

## Children's Privacy

The App is not directed to children under 13, and the App does not knowingly
collect personal information from children.

## Contact

If you have questions about this policy, please contact us:

- Email: nanomouse.official@gmail.com
- GitHub Issues: https://github.com/xjwhnxjwhn/nanomouse/issues

## Policy Updates

We may update this policy from time to time. Any changes will be posted on this
page with an updated "Last Updated" date.
