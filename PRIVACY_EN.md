# Privacy Policy

**Last Updated: February 9, 2026**

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

- Apple services (Speech, iCloud)
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
