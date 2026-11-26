# Privacy Policy

**Last updated November 26, 2026** · [中文](PRIVACY.md)

## Overview

NanoMouse is an open-source, cross-platform input method application. This policy explains how data is handled under different feature modes.

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
- **Photos and camera**: The App requests camera or photo permissions when
  you take a photo in Byte Paste, import images from Photos, or export images
  to your photo library. Photo selection for publishing is described below.
- **Diary protection**: When you view diary content, the App may use Face ID or
  the device passcode for on-device authentication.
- **Local network**: When you upload or manage input schema files through a
  browser, the App uses local network capability so devices on the same network
  can connect to the local service.
- **Product notifications**: The App requests notification permission only when
  you enable product notifications in the app, for product updates, important
  announcements, and service status notices.
- **Account activity notifications**: When you have allowed notifications and
  are signed in to a NanoMouse account, the App links the push device token
  assigned by the system to your account, to
  tell you about skin marketplace sales, review results, comments and replies,
  and community replies. A notification may include a work title and a short
  excerpt of a comment. The link stops being used or is deleted when you sign
  out, turn off notifications in Settings, or delete your account.

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

The app and keyboard store your consent on this device. The record contains recipient information, the data category, and disclosure version, never your text, audio, or API keys. Revocation prevents new transfers; it cannot undo completed transfers.

### Data and purposes

| Data category | Data sent and purposes |
| --- | --- |
| Text | Text you submit or select (including candidates, transcripts, diary content, and text recognized locally from screenshots), along with instructions, language settings, and necessary context, for rewriting, translation, cleanup, summarization, or analysis. Chat screenshot analysis does not send the original screenshot. |
| Speech recognition audio | The current recording, recognition language, and configured vocabulary hints, for transcription. Recordings may contain your voice and those of people nearby. |
| Speech generation inputs | Reading text, dialogue, delivery instructions, and voice settings, for audio synthesis. Reference voice features also send audio you record or import and its corresponding transcript; use only voices you have the right to share. |
| Search terms | Voice search terms you enter, for searching the voice catalog. |

### Recipients

**NanoMouse online services:** With your permission, NanoMouse shares the submitted content with providers listed on the permission screen. Data may be processed in mainland China, Japan, or elsewhere. We ask again before adding a recipient.

Disclosures and permission are specific to the China or overseas service region in use and the data category. Providers exclusive to the other region are excluded:

| Data category | China region | Overseas region |
| --- | --- | --- |
| Text processing | DeepSeek, OpenAI, Google, Alibaba Cloud, Zhipu AI, SiliconFlow | DeepSeek, OpenAI, Google |
| Online speech recognition | Alibaba Cloud, SiliconFlow | OpenAI, Google, Alibaba Cloud |
| Speech generation, reference voices, voice search | Fish Audio | Fish Audio |

When the default DeepSeek model is used, a [relay service](https://opencode.ai/legal/privacy-policy) forwards your submitted text and necessary context to DeepSeek for processing. Some rewrite and translation requests in the China region use Zhipu AI or SiliconFlow. OpenAI processes text for GPT models. Google processes text for Gemini and Gemma models. If you have not chosen a model for a task, its default model is used. The region identifies the NanoMouse service you connect to. Processing may take place elsewhere.

After a region change, a region without existing permission requires permission before content is sent.

Provider information: [DeepSeek](https://cdn.deepseek.com/policies/en-US/deepseek-privacy-policy.html), [Zhipu AI](https://open.bigmodel.cn/terms?view=privacy), [OpenAI](https://openai.com/policies/privacy-policy/), [Google](https://ai.google.dev/gemini-api/terms), [Alibaba Cloud](https://www.alibabacloud.com/help/en/legal/latest/alibaba-cloud-international-website-privacy-policy), [SiliconFlow](https://docs.siliconflow.cn/cn/legals/privacy-policy), [Fish Audio](https://fish.audio/privacy/).

**Your own API key or custom endpoint:** The app sends the corresponding content and required API key directly to the configured address. The permission screen identifies the actual destination domain. For custom proxies, verify the operator, any onward recipients, and their complete data practices. Ordinary requests using your own key do not pass through NanoMouse's AI relay.

### Third-party protection and retention

NanoMouse requires third parties entrusted with user data to provide protection at least equivalent to this policy and applicable privacy requirements, including defined purposes, appropriate security, access restrictions, and retention and deletion rules. Before enabling a managed route, we must verify the applicable service terms, account settings, and data processing agreement. A route that cannot meet those conditions must not process personal data. User permission does not override a provider's restrictions.

Provider retention periods, legal preservation, and deletion procedures depend on the applicable terms. Before using your own key or proxy, verify that the service permits processing the content you intend to send and review its data protection practices.

Except for AI Wish conversations described below, NanoMouse does not archive request text, recordings, reference audio, or AI output as persistent business content. For authentication, quotas, troubleshooting, and abuse prevention, the service records account identifiers, request IDs, time, provider/model, status, character or token usage, latency, and cost statistics, without storing content bodies in these usage records. Routine request records are retained for 30 days by default and daily usage records for 400 days. Security, disputes, or legal obligations may require appropriate additional retention.

### AI Wish conversation history

When you use an AI Wish screen that displays the history notice, the wish you send and recent context from that conversation are used to generate a keyboard appearance. NanoMouse stores newly submitted wishes that enter the generation process, the appearance changes returned by the AI, timestamps, and request status under your account and conversation. Follow-up wishes stay in the same thread. Automatic repair attempts and their replies are labeled and saved. Authorized team members can review the conversations to understand how people describe effects and how the model responds, and to improve the shared appearance glossary and its prompts. Other users cannot browse your conversations. Existing on-device conversations are not uploaded in bulk.

On iOS, your device stores your wishes and each generated design. Versions displaying this notice have no conversation count limit or automatic expiration. You can delete a conversation from this device in AI Wish history. The server copy is separate and has no automatic expiration. Deleting your NanoMouse account deletes its server conversations. You can also request deletion of server records at xjwhn@qq.com.

## Skin marketplace, community, and publishing from Photos

- **Publishing skins.** When you submit or update a skin, NanoMouse receives its title, description, scheme files, included backgrounds and fonts, and any preview images, animations, or videos you attach. Submissions are linked to your account. After approval, others can view the listing, your public author profile and previews, and obtain the skin under the marketplace terms. To check for prohibited content, NanoMouse may send the title, description, preview or background images, or selected video frames to OpenAI for moderation. You can review the publishing terms before submitting, or cancel.
- **Posts, replies, and comments.** NanoMouse associates the boards, posts, images, replies, and marketplace comments you submit with your account. Once published, other people can view and copy this content. NanoMouse also stores reports and block relationships to investigate complaints and filter content.
- **Choosing media.** You choose which items from Photos to attach to a forum post, use as a marketplace preview, or use as your avatar. NanoMouse receives those items when you submit the post or skin or save your profile. Your avatar appears on your public profile.
- **Removal and complaints.** You can delete your own forum posts or replies, withdraw a skin, report content, or block a user. Withdrawing a skin stops new acquisitions. Existing owners may still download it. For privacy or copyright complaints, contact xjwhn@qq.com and identify the listing or post.

## Accounts, purchases, and credentials

Permanent clipboard-slot unlocks can be purchased and restored through the App Store without registering a NanoMouse account.

Your account lets you sign in, manage online services and subscriptions, and publish to the marketplace or community. NanoMouse stores an account identifier, login sessions, and verified subscription associations. The information used for sign-in depends on your choice.

At registration, NanoMouse records the connection IP address to investigate automated registrations and abuse and enforce bans. Only authorized administrators can look it up. It is deleted with the account. Marketplace and community content is shown according to the mainland China or overseas region of the visiting IP address.


- **Email.** We send a verification code to your address when you register. The server stores your address, a password hash, and a time-limited verification record.
- **Passkeys.** The server stores a credential identifier and public key to verify sign-in signatures. Your credential manager holds the private key. NanoMouse does not receive your Face ID or fingerprint data.
- **Apple and other sign-in providers.** You authorize the provider, and NanoMouse uses the account identifier it returns to create or link your account. Google, LINE, Microsoft, or GitHub may be available, depending on which providers are enabled. Apple or Google may also provide an email address. The sign-in provider handles your password for that service. Versions that support automatic revocation send Apple a one-time sign-in code, store the credential Apple returns in encrypted form, and use it to revoke access when you delete your account. You can also stop using NanoMouse in your Apple Account.

The App Store processes in-app purchases. NanoMouse does not receive payment-card details. You can delete your NanoMouse account on its account page or contact us about a data request. To cancel an App Store subscription, use Apple’s subscription settings separately.

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
