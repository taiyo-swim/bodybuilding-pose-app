#!/usr/bin/env python3
"""
ポーズ学習スクリプト
動画ファイルからMediaPipeでポーズキーポイントを抽出し、DBに保存する。

使い方:
  # training_videos/ フォルダ内の動画をすべて処理（ファイル名=ポーズ名）
  python train_poses.py

  # 単一動画を指定ポーズ名で登録
  python train_poses.py path/to/video.mp4 --name front_double_bicep

  # フォルダを指定
  python train_poses.py path/to/folder/

  # DB内のポーズ一覧を表示
  python train_poses.py --list

  # DB内のポーズをすべて削除
  python train_poses.py --clear

フォルダ内の動画ファイル名（拡張子なし）がポーズ名として使用されます。
対応ポーズ名:
  front_double_bicep, front_lat_spread, most_muscular,
  side_chest, rear_lat_spread, side_tricep,
  abdominal_thigh, rear_double_bicep,
  hands_on_hips, vacuum, side_lat_spread, front_relaxed
"""

import sys
import argparse
from pathlib import Path

# backend パッケージを import できるようにプロジェクトルートをパスに追加
sys.path.insert(0, str(Path(__file__).parent))

from backend.database import init_db, save_pose, get_poses, get_connection
from backend.pose_extractor import extract_representative_pose

# ポーズ名ごとのデフォルトメタデータ
POSE_META: dict[str, dict] = {
    'front_double_bicep': {'category': 'competition', 'energy': 0.80},
    'front_lat_spread':   {'category': 'competition', 'energy': 0.60},
    'most_muscular':      {'category': 'competition', 'energy': 0.90},
    'side_chest':         {'category': 'competition', 'energy': 0.50},
    'rear_lat_spread':    {'category': 'competition', 'energy': 0.65},
    'side_tricep':        {'category': 'competition', 'energy': 0.45},
    'abdominal_thigh':    {'category': 'competition', 'energy': 0.75},
    'rear_double_bicep':  {'category': 'competition', 'energy': 0.80},
    'hands_on_hips':      {'category': 'transition',  'energy': 0.30},
    'vacuum':             {'category': 'competition', 'energy': 0.70},
    'side_lat_spread':    {'category': 'competition', 'energy': 0.55},
    'front_relaxed':      {'category': 'transition',  'energy': 0.25},
}

VIDEO_EXTENSIONS = {'.mp4', '.mov', '.avi', '.mkv', '.webm', '.m4v'}


def process_video(video_path: Path, pose_name: str, category: str, energy: float, replace: bool = True) -> bool:
    """動画からポーズを抽出してDBに保存する。成功したら True を返す。"""
    print(f"  処理中: {video_path.name} → '{pose_name}'")

    pose_data = extract_representative_pose(str(video_path))
    if not pose_data:
        print(f"  ✗ ポーズを検出できませんでした: {video_path.name}")
        return False

    keypoints = pose_data['keypoints']
    timestamp = pose_data.get('timestamp', 0)

    if replace:
        conn = get_connection()
        deleted = conn.execute("DELETE FROM poses WHERE name = ?", (pose_name,)).rowcount
        conn.commit()
        conn.close()
        if deleted:
            print(f"    既存ポーズを上書き (削除: {deleted}件)")

    pose_id = save_pose(pose_name, category, energy, keypoints)
    print(f"  ✓ 保存完了  id={pose_id}  timestamp={timestamp:.2f}s  keypoints={len(keypoints)}")
    return True


def list_poses() -> None:
    """DB内のポーズ一覧を表示する。"""
    poses = get_poses()
    if not poses:
        print("DBにポーズがありません。")
        return
    print(f"\nDB内のポーズ ({len(poses)}件):")
    print(f"{'ID':>4}  {'名前':<25} {'カテゴリ':<15} {'エネルギー':>10}")
    print("-" * 58)
    for p in poses:
        print(f"{p['id']:>4}  {p['name']:<25} {p['category']:<15} {p['energy_level']:>10.2f}")


def main() -> None:
    parser = argparse.ArgumentParser(
        description='ボディビルポーズ学習スクリプト',
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=__doc__,
    )
    parser.add_argument(
        'target', nargs='?', default='training_videos',
        help='動画ファイルまたはフォルダパス (デフォルト: training_videos/)',
    )
    parser.add_argument('--name', help='ポーズ名（単一ファイル指定時）')
    parser.add_argument('--category', default=None, help='カテゴリ: competition または transition')
    parser.add_argument('--energy', type=float, default=None, help='エネルギーレベル (0.0〜1.0)')
    parser.add_argument('--no-replace', action='store_true', help='同名ポーズを上書きしない')
    parser.add_argument('--list', action='store_true', help='DBのポーズ一覧を表示して終了')
    parser.add_argument('--clear', action='store_true', help='DBのポーズをすべて削除して終了')
    args = parser.parse_args()

    init_db()

    if args.list:
        list_poses()
        return

    if args.clear:
        conn = get_connection()
        count = conn.execute("SELECT COUNT(*) FROM poses").fetchone()[0]
        conn.execute("DELETE FROM poses")
        conn.commit()
        conn.close()
        print(f"✓ DBのポーズをすべて削除しました ({count}件)")
        return

    target = Path(args.target)
    replace = not args.no_replace
    success = error = 0

    if target.is_file():
        # 単一ファイルを処理
        pose_name = args.name or target.stem
        meta = POSE_META.get(pose_name, {'category': 'custom', 'energy': 0.5})
        category = args.category or meta['category']
        energy = args.energy if args.energy is not None else meta['energy']
        ok = process_video(target, pose_name, category, energy, replace)
        success += ok
        error += not ok

    elif target.is_dir():
        # フォルダ内の動画をすべて処理
        videos = sorted(f for f in target.iterdir() if f.suffix.lower() in VIDEO_EXTENSIONS)
        if not videos:
            print(f"動画ファイルが見つかりません: {target}/")
            print(f"対応形式: {', '.join(sorted(VIDEO_EXTENSIONS))}")
            sys.exit(1)
        print(f"\n{len(videos)}件の動画を処理します: {target}/\n")
        for video in videos:
            pose_name = args.name or video.stem
            meta = POSE_META.get(pose_name, {'category': 'custom', 'energy': 0.5})
            category = args.category or meta['category']
            energy = args.energy if args.energy is not None else meta['energy']
            ok = process_video(video, pose_name, category, energy, replace)
            success += ok
            error += not ok

    else:
        print(f"エラー: パスが存在しません: {target}")
        print("使い方: python train_poses.py [動画ファイルまたはフォルダパス]")
        sys.exit(1)

    print(f"\n完了: {success}件成功 / {error}件失敗")
    if success > 0:
        list_poses()


if __name__ == '__main__':
    main()
