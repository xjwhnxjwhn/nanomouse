# Privacy Policy

**Last Updated: September 25, 2026**

## Overview

NanoMouse is an open-source, cross-platform input method application. We take
privacy seriously, and we keep processing on-device whenever possible. This
policy explains how data is handled under different feature modes.

## Data Processing Principles

- The App uses local processing by default.
- The App does not upload your data to NanoMouse-operated servers for ads or
  analytics.
- When you use online AI and consent to sharing, content is forwarded through
  NanoMouse or sent directly to the third-party service you configure.

## What Data Is Processed

### 1) Keyboard Input Content

- Regular text input is processed locally by default.
- The App does not include third-party ad SDKs.
- The App does not include third-party analytics SDKs.

### 2) Voice Dictation (ASR)

The microphone is used for dictation, conversation translation, reference recordings,
and voice standby that you explicitly start. Compact and standard floating modes
do not capture idle audio. The no-window mode keeps the microphone active with
the system microphone indicator; idle buffers are discarded without saving.
Recognition begins when you start dictation. Disabling standby stops this capture.

The App supports multiple speech recognition routes. The actual data flow is
based on your settings:

- **Apple Speech**: Processed by Apple system speech capabilities.
- **Offline speech recognition**: Processed on-device with local models.
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

## Online AI: disclosure before permission

Before first sending a category of data to a group of recipients, the app explains the data, purpose, recipients, and their privacy information, and asks for your affirmative permission. Text, online speech recognition, speech generation, reference audio, and voice searches have separate permissions. Allowing text-to-speech does not authorize uploading reference audio.

Launching the app does not request these five AI permissions. When an online feature needs to send data without an existing permission, the app automatically displays the relevant disclosure. A keyboard request automatically opens that disclosure in the main app, without requiring navigation through settings. Declining or closing does not send the content; the next use automatically asks again.

You can revoke AI permissions under **Settings → General → View Privacy & Permissions → AI Data Permissions**. Declining does not affect ordinary typing, offline recognition, or purchased clipboard slots. Changes to the recipients, data category, or disclosure version presented in the app require new permission. The corresponding content is not sent before permission is obtained.

Once granted, consent is stored in the shared app container for reuse by the app and keyboard. Subsequent checks read this local record without making an additional network request. They contain recipient information, the data category, and disclosure version, never your text, audio, or API keys. Revocation prevents new transfers; it cannot undo completed transfers.

### Data and purposes

| Data category | Data sent and purposes |
| --- | --- |
| Text | Text you submit or select (including candidates, transcripts, diary content, and text recognized locally from screenshots), along with instructions, language settings, and necessary context, for rewriting, translation, cleanup, summarization, or analysis. Chat screenshot analysis does not send the original screenshot. |
| Speech recognition audio | The current recording, recognition language, and configured vocabulary hints, for transcription. Recordings may contain your voice and those of people nearby. |
| Speech generation inputs | Reading text, dialogue, delivery instructions, and voice settings, for audio synthesis. Reference voice features also send audio you record or import and its corresponding transcript; use only voices you have the right to share. |
| Search terms | Voice search terms you enter, for searching the voice catalog. |

### Recipients

**NanoMouse online services:** Content goes through NanoMouse online services for authentication, quota management, and forwarding, then to an AI provider listed in the permission screen. Services operate in Japan and mainland China; some requests may pass through NanoMouse's other region. Before enabling a recipient outside that list, we must update the in-app disclosure and obtain new permission. NanoMouse does not forward your NanoMouse login token, Apple identity token, or email address to AI providers.

Disclosures and permission are specific to the China or overseas service region in use and the data category. Providers exclusive to the other region are excluded:

| Data category | China region | Overseas region |
| --- | --- | --- |
| Text processing | Alibaba Cloud, Zhipu AI, SiliconFlow | Google |
| Online speech recognition | Alibaba Cloud | Google, Alibaba Cloud |
| Speech generation, reference voices, voice search | Fish Audio | Fish Audio |

After a region change, a region without existing permission requires permission before content is sent. Services marked “Coming Soon” are not current recipients or included in the permission.

Provider information: [Google](https://ai.google.dev/gemini-api/terms), [Alibaba Cloud](https://www.alibabacloud.com/help/en/legal/latest/alibaba-cloud-international-website-privacy-policy), [Zhipu AI](https://open.bigmodel.cn/terms?view=privacy), [SiliconFlow](https://docs.siliconflow.cn/cn/legals/privacy-policy), [Fish Audio](https://fish.audio/privacy/).

**Your own API key or custom endpoint:** The app sends the corresponding content and required API key directly to the configured address. The permission screen identifies the actual destination domain. For custom proxies, verify the operator, any onward recipients, and their complete data practices. Ordinary requests using your own key do not pass through NanoMouse's AI relay.

### Third-party protection and retention

NanoMouse requires third parties entrusted with user data to provide protection at least equivalent to this policy and applicable privacy requirements, including defined purposes, appropriate security, access restrictions, and retention and deletion rules. Before enabling a managed route, we must verify the applicable service terms, account settings, and data processing agreement. A route that cannot meet those conditions must not process personal data. User permission does not override a provider's restrictions.

Provider retention periods, legal preservation, and deletion procedures depend on the applicable terms. Before using your own key or proxy, verify that the service permits processing the content you intend to send and review its data protection practices.

NanoMouse's AI relay does not archive request text, recordings, reference audio, or AI output as persistent business content. Processing uses memory or temporary request files. For authentication, quotas, troubleshooting, and abuse prevention, the service records account identifiers, request IDs, time, provider/model, status, character or token usage, latency, and cost statistics, without storing content bodies in these usage records. Routine request records are retained for 30 days by default and daily usage records for 400 days. Security, disputes, or legal obligations may require appropriate additional retention.

## Accounts, purchases, and credentials

Permanent clipboard-slot unlocks can be purchased and restored through the App Store without registering a NanoMouse account.

NanoMouse AI accounts manage online eligibility, trials, subscription synchronization, and usage. Sign in with Apple provides an account identifier and email address, if supplied. The service stores account status, sessions, and verified subscription associations. The App Store processes payment; we do not receive payment-card information. You can delete your NanoMouse account from its account page or contact us about data requests. Account deletion does not automatically cancel an App Store subscription; manage subscriptions through Apple.

## Third-Party Services

When corresponding features are enabled, the App may interact with:

- Apple services and system frameworks (Speech, iCloud/CloudKit, WeatherKit,
  notifications, location, Photos, and camera permission frameworks)
- Providers identified in the AI permission disclosures above and services you configure

Data handling by those providers is governed by their own privacy policies.

## Your Controls

You can, at any time:

- Revoke AI sharing permission in Privacy & Permissions → AI Data Permissions
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
