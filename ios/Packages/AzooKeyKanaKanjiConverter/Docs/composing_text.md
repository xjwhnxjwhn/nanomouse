#  ComposingText API

AzooKeyKanaKanjiConverterにおいて、変換を要求するには`ComposingText`のAPIを使う必要があります。この`ComposingText` APIについて説明します。

## 基本的なアイデア

`ComposingText`の基本的なアイデアは「入力操作との対応」です。ユーザが日本語IMEを操作するとき、「きょうはいいてんきですね」と一文字ずつ入力することもあれば、「kyouhaiitenkidesune」のようにローマ字入力を行うこともあります。azooKeyでは前者をダイレクト入力、後者をローマ字入力と呼んでいます。`ComposingText`はこのような入力操作をうまく扱いながら、変換を逐次的に実行するために役立ちます。

## 基本的な使い方

`ComposingText`を使い始めるには、まず空の値を作ります。

```swift
var composingText = ComposingText()
```

次に、末尾に文字を追加します。このために使うのが`insertAtCursorPosition`です。

```swift
composingText.insertAtCursorPosition("あ", inputStyle: .direct)
```


このとき、`ComposingText`の内部状態は次のようになっています。


```swift
print(composingText.input)                        // [InputElement("あ", .direct)]
print(composingText.convertTargetCursorPosition)  // 1 (あ|)
print(composingText.convertTarget)                // あ
```

非常に自明です。ではローマ字入力の場合はどうなるでしょうか。

```swift
composingText.insertAtCursorPosition("o", inputStyle: .roman2kana)
```

この場合は少し異なることが起こります。`input`に`"o"`が正しく保存されるのです。


```swift
print(composingText.input)                        // [InputElement("あ", .direct), InputElement("o", .roman2kana)]
print(composingText.convertTargetCursorPosition)  // 2 (あお|)
print(composingText.convertTarget)                // あお
```

一方、`convertTarget`の方は正しくローマ字入力した仮名表記になっています。このように`convertTarget`の方はユーザに実際に見える「見かけの文字列」であり、実装側はこれが実際にユーザに見えているよう保障する必要があります。`convertTargetCursorPosition`についても同様で、実装側は`convertTargetCursorPosition`に示されたカーソル位置が実際にユーザに見えているカーソル位置と一致するよう配慮する必要があります。

## 操作するAPI

### 削除

`deleteForwardFromCursorPosition`および`deleteBackwardFromCursorPosition`が使えます。


### カーソル移動

`moveCursorFromCursorPosition`が使えます。


### 文頭の削除

`prefixComplete`が使えます。


### 置換

専用のAPIはありません。削除と挿入で代用してください。

## PCのキー入力を扱う（試験的）

PCキーボードからの入力を、キーと修飾キーの組み合わせとして扱うために、内部的に `InputPiece.key(intention: Character?, modifiers: Set<Modifier>)` をサポートしています（現状の修飾は `shift` のみ）。

カスタム入力テーブルでは `{shift 0}` と `{shift _}` の2トークンのみを特別扱いでサポートしており、それぞれ `.key(intention: "0", [.shift])`、`.key(intention: "_", [.shift])` に対応します。`ComposingText` に投入する場合は、以下のように `InputElement(piece: …, inputStyle: …)` を使います。

```swift
let table = try InputStyleManager.loadTable(from: url)
InputStyleManager.registerInputStyle(table: table, for: "custom_table")

var c = ComposingText()
c.insertAtCursorPosition([
    .init(piece: .key(intention: "0", modifiers: [.shift]), inputStyle: .mapped(id: .tableName("custom_table")))
])
```

マッチングの優先順位は「キー規則（例: `{shift 0}`）」が「文字規則（例: `0`）」よりも優先されます。同じ意図文字を持つキー入力は、文字規則にもフォールバックして一致します。また、`{any character}` はキー入力の意図文字にも一致し、出力の `{any character}` に代入されます。
