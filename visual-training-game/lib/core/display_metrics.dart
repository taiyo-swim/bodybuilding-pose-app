import 'package:flutter/foundation.dart';

import 'viewing_geometry.dart';

/// 端末から [ViewingGeometry] を組み立てる。
///
/// 未決事項A の暫定方針「ppi補正のみ・視距離40cm固定」の入口（仕様書 0-A）。
///
/// 論理px/inch はプラットフォームの**定義**（Android 1dp = 1/160 inch、
/// iOS 1pt ≈ 1/163 inch）から決まるため、devicePixelRatio には依存しない。
/// 一方で実機の物理ppi はこの定義値から数%〜十数%ずれる。
///
/// TODO(未決): 未決事項A が確定したら、ここを実ppi の取得経路
/// （機種データベース、またはキャリブレーション結果）に差し替える。
/// ランキングの公平性はこの値の精度に直結する（仕様書 0-A）。
ViewingGeometry currentViewingGeometry({TargetPlatform? platform}) {
  final TargetPlatform effective = platform ?? defaultTargetPlatform;
  final bool isIOS =
      effective == TargetPlatform.iOS || effective == TargetPlatform.macOS;
  return ViewingGeometry(
    logicalPixelsPerInch: DisplayDensity.nominalLogicalPixelsPerInch(
      isIOS: isIOS,
    ),
  );
}
