SimpleAVPlayer
===========


## ToDo

- Write Super Cool README.
- Make Ultra Cool Sample App.


## What is this

`AVPlayerLayer` を `UIKit` の世界に持ってきて KVO で大体いつも監視するやつを delegate パターンに追い出したやつ。

ついでに作ったつもりがメインになってしまったんだけど、 `AVPlayer` に `AVPlayerItemVideoOutput` を放り込んで `CADisplayLink` のタイミングでピクセルバッファを取って `CIImage` にしつつリアルタイムに `CIFilter` で処理して GPU で描画するみたいなやつもある。


## Poem

最近の iOS 界隈というか Swift 界隈、型に厳密でクールでお洒落なライブラリじゃないとダサいみたいな風潮あると思うんだけど、完全に個人で自分が使うためだけに書いたというか、知らん、これは俺が使うんだ！！！俺こそがユーザーだ！！！


## Carthage

https://github.com/Carthage/Carthage

Write your `Cartfile`

```
github "dnpp73/SimpleAVPlayer"
```

and run

```sh
carthage bootstrap --no-use-binaries --platform iOS
```


## How to Use

### See `Interface.swift`

- [`PlayerControlInterface.swift`](/SimpleAVPlayer/PlayerControlInterface.swift)


## License

[MIT](/LICENSE)
