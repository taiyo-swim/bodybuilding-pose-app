import * as THREE from 'three'
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js'
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js'
import type { Pose } from '../types'

// ── 定義済みポーズ（Mixamo GLBボーン用 Euler XYZ rad） ──────────────
// Mixamo 座標系: LeftArm はローカル+X方向が腕の向き
//   Z回転 ≈ 腕の上下（+= 上がる）, Y回転 ≈ 前後内外, X回転 ≈ ひねり
const POSE_ROTATIONS: Record<string, Record<string, [number, number, number]>> = {
  // 1. フロントダブルバイセップス
  //    両腕を肩の高さに水平に上げ、肘を90度屈曲、拳を上に向ける
  front_double_bicep: {
    LeftArm:      [0.15,  0.10,  1.57], LeftForeArm:  [0, -1.57,  0],
    RightArm:     [0.15, -0.10, -1.57], RightForeArm: [0,  1.57,  0],
    LeftShoulder: [0, 0, 0.15], RightShoulder: [0, 0, -0.15],
    Spine: [-0.08, 0, 0], Spine1: [-0.05, 0, 0],
  },
  // 2. フロントラットスプレッド
  //    腕を腰の横で外に張り、背中を広げてVシェイプを作る
  front_lat_spread: {
    LeftArm:      [0.10,  0.20,  0.70], LeftForeArm:  [0.10, -0.35, 0],
    RightArm:     [0.10, -0.20, -0.70], RightForeArm: [0.10,  0.35, 0],
    LeftShoulder: [0, 0, 0.35], RightShoulder: [0, 0, -0.35],
    Spine: [0.12, 0, 0], Spine1: [0.08, 0, 0], Spine2: [0.05, 0, 0],
  },
  // 3. モストマスキュラー（クラブポーズ）
  //    前傾み、腕を内側・前方に引き寄せ、僧帽筋・肩・胸を強調
  most_muscular: {
    LeftArm:  [0.55,  0.60,  0.55], LeftForeArm:  [0.30, -1.30,  0.40],
    RightArm: [0.55, -0.60, -0.55], RightForeArm: [0.30,  1.30, -0.40],
    LeftShoulder: [0, 0, 0.20], RightShoulder: [0, 0, -0.20],
    Spine: [0.35, 0, 0], Spine1: [0.28, 0, 0], Spine2: [0.18, 0, 0],
    Neck: [0.25, 0, 0],
  },
  // 4. サイドチェスト（左側面を客席に向ける）
  //    体を90度回転、胸を前に突き出し、片腕を曲げ胸を強調
  side_chest: {
    Hips: [0, -1.40, 0], Spine: [0, 0.35, 0], Spine1: [0, 0.15, 0],
    // 手前の腕（左腕）：肘を曲げ胸に密着
    LeftArm:  [0.30,  0.80,  1.00], LeftForeArm:  [0.15, -1.40, 0],
    // 奥の腕（右腕）：体の後ろに回す
    RightArm: [0.20, -0.40, -0.80], RightForeArm: [0.10,  0.80, 0],
  },
  // 5. リアラットスプレッド（後ろ向き）
  //    後ろを向いて背中の広がりを見せる
  rear_lat_spread: {
    Hips: [0, Math.PI, 0],
    LeftArm:      [0.15,  0.10,  0.70], LeftForeArm:  [0.05, -0.35, 0],
    RightArm:     [0.15, -0.10, -0.70], RightForeArm: [0.05,  0.35, 0],
    LeftShoulder: [0, 0, 0.35], RightShoulder: [0, 0, -0.35],
    Spine: [0.10, 0, 0], Spine1: [0.08, 0, 0],
  },
  // 6. サイドトライセップス（左側面）
  //    体を側面に向け、腕を後ろに伸ばして上腕三頭筋を強調
  side_tricep: {
    Hips: [0, -1.40, 0], Spine: [0, 0.25, 0],
    // 手前の腕：後ろに伸ばして三頭筋見せる
    LeftArm:  [-0.15,  1.00,  0.10], LeftForeArm:  [0.05, -0.15, 0],
    // 奥の腕：自然な位置
    RightArm: [ 0.30, -0.80, -0.65], RightForeArm: [0.10,  0.15, 0],
  },
  // 7. アブドミナルアンドサイ（腹筋と大腿）
  //    両腕を上げて肘から後方に引き、腹筋を収縮
  abdominal_thigh: {
    LeftArm:  [0.20,  0.20,  1.40], LeftForeArm:  [0, -0.45, 0],
    RightArm: [0.20, -0.20, -1.40], RightForeArm: [0,  0.45, 0],
    Spine: [-0.20, 0, 0], Spine1: [-0.15, 0, 0],
  },
  // 8. リアダブルバイセップス（後ろ向き）
  rear_double_bicep: {
    Hips: [0, Math.PI, 0],
    LeftArm:      [0.15,  0.10,  1.57], LeftForeArm:  [0, -1.57, 0],
    RightArm:     [0.15, -0.10, -1.57], RightForeArm: [0,  1.57, 0],
    LeftShoulder: [0, 0, 0.15], RightShoulder: [0, 0, -0.15],
    Spine: [-0.08, 0, 0], Spine1: [-0.05, 0, 0],
  },
  // 追加ポーズ
  hands_on_hips: {
    LeftArm:  [0.10,  0.30,  0.60], LeftForeArm:  [0.15, -1.00, 0],
    RightArm: [0.10, -0.30, -0.60], RightForeArm: [0.15,  1.00, 0],
    Spine: [0.05, 0, 0],
  },
  vacuum: {
    LeftArm:  [0.10,  0.20,  1.55], LeftForeArm:  [0, -0.40, 0],
    RightArm: [0.10, -0.20, -1.55], RightForeArm: [0,  0.40, 0],
    Spine: [-0.28, 0, 0], Spine1: [-0.22, 0, 0], Spine2: [-0.12, 0, 0],
  },
  side_lat_spread: {
    Hips: [0, -1.40, 0], Spine: [0, 0.25, 0],
    LeftArm:  [0.10,  0.10,  0.70], LeftForeArm:  [0.05, -0.40, 0],
    RightArm: [0.40, -0.65, -1.10], RightForeArm: [0.10,  0.75, 0],
    LeftShoulder: [0, 0, 0.30],
  },
  front_relaxed: {
    LeftArm:  [0, 0,  0.20], LeftForeArm:  [0, 0, 0],
    RightArm: [0, 0, -0.20], RightForeArm: [0, 0, 0],
    Spine: [0.03, 0, 0],
  },
}

// ── プレースホルダー用ポーズ定義 ─────────────────────────────────────
type PhPose = { lZ: number; rZ: number; lX: number; lY: number; rX: number; rY: number; tX: number }
const REST_PH: PhPose = { lZ: 0.15, rZ: -0.15, lX: -0.29, lY: 1.35, rX: 0.29, rY: 1.35, tX: 0 }
const PLACEHOLDER_POSES: Record<string, PhPose> = {
  front_double_bicep: { lZ: -1.40, rZ:  1.40, lX: -0.46, lY: 1.56, rX:  0.46, rY: 1.56, tX: -0.05 },
  front_lat_spread:   { lZ: -0.80, rZ:  0.80, lX: -0.40, lY: 1.42, rX:  0.40, rY: 1.42, tX:  0.08 },
  most_muscular:      { lZ: -0.90, rZ:  0.90, lX: -0.38, lY: 1.44, rX:  0.38, rY: 1.44, tX:  0.22 },
  side_chest:         { lZ: -0.50, rZ: -1.10, lX: -0.25, lY: 1.38, rX:  0.22, rY: 1.48, tX:  0.08 },
  rear_lat_spread:    { lZ: -0.80, rZ:  0.80, lX: -0.40, lY: 1.42, rX:  0.40, rY: 1.42, tX: -0.05 },
  side_tricep:        { lZ: -0.20, rZ: -0.90, lX: -0.22, lY: 1.32, rX:  0.28, rY: 1.40, tX:  0.05 },
  abdominal_thigh:    { lZ: -1.10, rZ:  1.10, lX: -0.42, lY: 1.50, rX:  0.42, rY: 1.50, tX: -0.10 },
  rear_double_bicep:  { lZ: -1.40, rZ:  1.40, lX: -0.46, lY: 1.56, rX:  0.46, rY: 1.56, tX: -0.05 },
  hands_on_hips:      { lZ: -0.50, rZ:  0.50, lX: -0.34, lY: 1.20, rX:  0.34, rY: 1.20, tX:  0.03 },
  vacuum:             { lZ: -1.50, rZ:  1.50, lX: -0.48, lY: 1.58, rX:  0.48, rY: 1.58, tX: -0.18 },
  side_lat_spread:    { lZ: -0.80, rZ: -1.00, lX: -0.40, lY: 1.42, rX:  0.22, rY: 1.44, tX:  0.05 },
  front_relaxed:      { lZ:  0.15, rZ: -0.15, lX: -0.29, lY: 1.35, rX:  0.29, rY: 1.35, tX:  0.03 },
}

const BONE_REST_DIRS: Record<string, THREE.Vector3> = {
  LeftArm:      new THREE.Vector3( 1, 0, 0),
  LeftForeArm:  new THREE.Vector3( 1, 0, 0),
  RightArm:     new THREE.Vector3(-1, 0, 0),
  RightForeArm: new THREE.Vector3(-1, 0, 0),
  LeftUpLeg:    new THREE.Vector3( 0,-1, 0),
  LeftLeg:      new THREE.Vector3( 0,-1, 0),
  RightUpLeg:   new THREE.Vector3( 0,-1, 0),
  RightLeg:     new THREE.Vector3( 0,-1, 0),
}

const MP_TO_BONE: Record<string, { bone: string; parent: string; child: string }> = {
  left_shoulder:  { bone: 'LeftArm',      parent: 'left_shoulder',  child: 'left_elbow'  },
  left_elbow:     { bone: 'LeftForeArm',  parent: 'left_elbow',     child: 'left_wrist'  },
  right_shoulder: { bone: 'RightArm',     parent: 'right_shoulder', child: 'right_elbow' },
  right_elbow:    { bone: 'RightForeArm', parent: 'right_elbow',    child: 'right_wrist' },
  left_hip:       { bone: 'LeftUpLeg',    parent: 'left_hip',       child: 'left_knee'   },
  left_knee:      { bone: 'LeftLeg',      parent: 'left_knee',      child: 'left_ankle'  },
  right_hip:      { bone: 'RightUpLeg',   parent: 'right_hip',      child: 'right_knee'  },
  right_knee:     { bone: 'RightLeg',     parent: 'right_knee',     child: 'right_ankle' },
}

export class Viewer3D {
  private renderer: THREE.WebGLRenderer
  private scene: THREE.Scene
  private camera: THREE.PerspectiveCamera
  private controls: OrbitControls
  private clock = new THREE.Clock()
  private model: THREE.Group | null = null
  private bones: Record<string, THREE.Bone> = {}
  private bonesByBaseName: Record<string, THREE.Bone> = {}
  private targetRotations: Record<string, THREE.Quaternion> = {}
  private placeholder: THREE.Group | null = null
  private idleTime = 0
  private beatScale = 1.0
  private modelBaseScale = 1.0
  private rafId = 0
  private ro: ResizeObserver | null = null
  private phLeftArm: THREE.Mesh | null = null
  private phRightArm: THREE.Mesh | null = null
  private phTorso: THREE.Mesh | null = null
  private phTarget: PhPose = { ...REST_PH }
  private bindPoseQuaternions: Record<string, THREE.Quaternion> = {}
  private transitionSource: Record<string, THREE.Quaternion> = {}
  private transitionProgress = 1.0
  private readonly TRANS_DUR = 0.8

  constructor(private container: HTMLElement) {
    // ── レンダラー ─────────────────────────────────────────────────────
    this.renderer = new THREE.WebGLRenderer({ antialias: true, alpha: true })
    this.renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2))
    this.renderer.shadowMap.enabled = true
    this.renderer.shadowMap.type = THREE.PCFSoftShadowMap
    this.renderer.outputColorSpace = THREE.SRGBColorSpace

    // canvas をコンテナの左上に絶対配置し、コンテナと同サイズにする
    const el = this.renderer.domElement
    el.style.position = 'absolute'
    el.style.top = '0'
    el.style.left = '0'
    this.container.style.position = 'relative'  // 親が relative でなければ設定
    this.container.appendChild(el)

    // ── シーン ────────────────────────────────────────────────────────
    this.scene = new THREE.Scene()

    // ── カメラ ────────────────────────────────────────────────────────
    this.camera = new THREE.PerspectiveCamera(40, 1, 0.1, 50)
    this.camera.position.set(0, 1.4, 3.8)

    // ── コントロール ──────────────────────────────────────────────────
    this.controls = new OrbitControls(this.camera, el)
    this.controls.target.set(0, 0.9, 0)
    this.controls.enableDamping = true
    this.controls.dampingFactor = 0.07
    this.controls.minDistance = 1.0
    this.controls.maxDistance = 7.0

    // ── ライト ────────────────────────────────────────────────────────
    this.scene.add(new THREE.AmbientLight(0xffffff, 0.5))
    const key = new THREE.DirectionalLight(0xfff0e0, 1.4)
    key.position.set(2, 4, 3); key.castShadow = true
    this.scene.add(key)
    const fill = new THREE.DirectionalLight(0xc0d8ff, 0.4)
    fill.position.set(-3, 2, -1)
    this.scene.add(fill)
    const rim = new THREE.DirectionalLight(0xe8c84a, 0.6)
    rim.position.set(0, 3, -4)
    this.scene.add(rim)
    const spot = new THREE.SpotLight(0xe8c84a, 3, 9, Math.PI / 7, 0.6)
    spot.position.set(0, 6, 0); this.scene.add(spot, spot.target)

    // ── ステージ ──────────────────────────────────────────────────────
    const stage = new THREE.Mesh(
      new THREE.CylinderGeometry(1.4, 1.4, 0.06, 64),
      new THREE.MeshStandardMaterial({ color: 0x18182a, metalness: 0.4, roughness: 0.6 })
    )
    stage.position.y = -0.03; stage.receiveShadow = true; this.scene.add(stage)

    // ── リサイズ ──────────────────────────────────────────────────────
    this.resize()
    // ResizeObserver でコンテナサイズ変化に追従
    this.ro = new ResizeObserver(() => this.resize())
    this.ro.observe(this.container)
    window.addEventListener('resize', () => this.resize())

    // ── アニメーションループ開始 ──────────────────────────────────────
    this.animate()
  }

  private resize() {
    const w = this.container.clientWidth  || 800
    const h = this.container.clientHeight || 600
    this.renderer.setSize(w, h)   // Three.js が canvas の CSS サイズも更新
    this.camera.aspect = w / h
    this.camera.updateProjectionMatrix()
  }

  private animate() {
    this.rafId = requestAnimationFrame(() => this.animate())
    const delta = Math.min(this.clock.getDelta(), 0.1)
    this.idleTime += delta

    // GLBモデルのボーンアニメーション
    if (this.model) {
      if (this.transitionProgress < 1.0) {
        // トランジション中: ソースからターゲットへ固定時間でslerp
        this.transitionProgress = Math.min(1.0, this.transitionProgress + delta / this.TRANS_DUR)
        const t = this.easeInOut(this.transitionProgress)
        for (const [name, tq] of Object.entries(this.targetRotations)) {
          const bone = this.findBone(name)
          if (!bone) continue
          const sq = this.transitionSource[name]
          if (sq) bone.quaternion.copy(sq).slerp(tq, t)
          else bone.quaternion.slerp(tq, t)
        }
      } else {
        // トランジション完了後: ターゲット位置を維持（spine以外）
        for (const [name, tq] of Object.entries(this.targetRotations)) {
          if (name === 'Spine') continue
          const bone = this.findBone(name)
          if (bone) bone.quaternion.copy(tq)
        }
      }
      // Spineの呼吸アニメーション（常にターゲット基準で適用）
      const spine = this.findBone('Spine')
      const spineTarget = this.targetRotations['Spine']
      if (spine) {
        if (spineTarget && this.transitionProgress >= 1.0) spine.quaternion.copy(spineTarget)
        spine.rotation.x += Math.sin(this.idleTime * 0.8) * 0.003
        spine.rotation.z += Math.sin(this.idleTime * 0.4) * 0.002
      }
    }

    // プレースホルダーアニメーション
    if (this.placeholder) {
      const s = Math.min(5.0 * delta, 0.12)
      if (this.phLeftArm) {
        this.phLeftArm.rotation.z  += (this.phTarget.lZ - this.phLeftArm.rotation.z) * s
        this.phLeftArm.position.x  += (this.phTarget.lX - this.phLeftArm.position.x) * s
        this.phLeftArm.position.y  += (this.phTarget.lY - this.phLeftArm.position.y) * s
      }
      if (this.phRightArm) {
        this.phRightArm.rotation.z += (this.phTarget.rZ - this.phRightArm.rotation.z) * s
        this.phRightArm.position.x += (this.phTarget.rX - this.phRightArm.position.x) * s
        this.phRightArm.position.y += (this.phTarget.rY - this.phRightArm.position.y) * s
      }
      if (this.phTorso) {
        this.phTorso.rotation.x += (this.phTarget.tX - this.phTorso.rotation.x) * s
        this.phTorso.rotation.z  = Math.sin(this.idleTime * 0.7) * 0.008
      }
    }

    if (this.beatScale > 1.0) {
      this.beatScale = Math.max(1.0, this.beatScale - delta * 3.0)
      if (this.model)       this.model.scale.setScalar(this.modelBaseScale * this.beatScale)
      if (this.placeholder) this.placeholder.scale.setScalar(this.beatScale)
    }

    this.controls.update()
    this.renderer.render(this.scene, this.camera)
  }

  private findBone(name: string): THREE.Bone | undefined {
    return (
      this.bones[name] ??
      this.bonesByBaseName[name] ??
      this.bones[`mixamorig:${name}`] ??
      this.bones[`mixamorig${name}`] ??
      this.bones[`mixamorig1_${name}`]
    )
  }

  // ── GLBモデル読み込み ─────────────────────────────────────────────
  loadModel(url: string): Promise<void> {
    return new Promise((resolve, reject) => {
      if (this.model) {
        this.scene.remove(this.model)
        this.model = null; this.bones = {}; this.bonesByBaseName = {}; this.targetRotations = {}
      }
      new GLTFLoader().load(
        url,
        (gltf) => {
          this.model = gltf.scene
          this.model.traverse((node) => {
            const mesh = node as THREE.Mesh
            const bone = node as THREE.Bone
            if (mesh.isMesh) { mesh.castShadow = true; mesh.receiveShadow = true }
            if (bone.isBone)  this.bones[node.name] = bone
          })
          console.log('[Viewer3D] Bones loaded:', Object.keys(this.bones).length, 'Sample:', Object.keys(this.bones).slice(0,5))
          // プレフィックスを除去してベース名でも引けるようにする
          this.bonesByBaseName = {}
          for (const [name, bone] of Object.entries(this.bones)) {
            const base = name.replace(/^mixamorig\d*[_:]?/, '')
            if (base && !this.bonesByBaseName[base]) {
              this.bonesByBaseName[base] = bone
            }
          }
          // バインドポーズ（初期ボーン回転）を保存
          this.bindPoseQuaternions = {}
          for (const [base, bone] of Object.entries(this.bonesByBaseName)) {
            this.bindPoseQuaternions[base] = bone.quaternion.clone()
          }
          // モデルを 1.7m 相当にスケール調整
          const box   = new THREE.Box3().setFromObject(this.model)
          const sizeY = box.getSize(new THREE.Vector3()).y
          const scale = sizeY > 0 ? 1.7 / sizeY : 1
          this.modelBaseScale = scale
          this.model.scale.setScalar(scale)
          const center = box.getCenter(new THREE.Vector3())
          this.model.position.set(-center.x * scale, -box.min.y * scale, -center.z * scale)
          this.scene.add(this.model)
          this.hidePlaceholder()   // ロード成功後にプレースホルダーを除去
          setTimeout(() => this.transitionToPose('front_double_bicep'), 800)
          resolve()
        },
        undefined,
        (err) => { console.error('[Viewer3D] loadModel error:', err); reject(err) }
      )
    })
  }

  transitionToPose(poseName: string, keypoints?: Pose['keypoints'] | null) {
    if (this.model) {
      keypoints ? this.applyKeypointPose(keypoints) : this.applyPredefinedPose(poseName)
    } else if (this.placeholder) {
      this.applyPlaceholderPose(poseName)
    }
  }

  private applyPredefinedPose(poseName: string) {
    const pose = POSE_ROTATIONS[poseName]
    if (!pose) { this.resetPose(); return }
    const allBones = ['LeftArm','LeftForeArm','RightArm','RightForeArm',
                      'LeftUpLeg','LeftLeg','RightUpLeg','RightLeg',
                      'Spine','Spine1','Spine2','Neck','Hips','LeftShoulder','RightShoulder']
    // 現在のボーン回転をトランジション開始点としてキャプチャ
    this.transitionSource = {}
    for (const name of allBones) {
      const bone = this.findBone(name)
      if (bone) this.transitionSource[name] = bone.quaternion.clone()
    }
    // targetRotations を一度クリアして全ボーンを再設定（古いターゲットの残留を防ぐ）
    this.targetRotations = {}
    this.transitionProgress = 0.0
    for (const name of allBones) {
      this.targetRotations[name] = pose[name]
        ? new THREE.Quaternion().setFromEuler(new THREE.Euler(...(pose[name] as [number,number,number]), 'XYZ'))
        : (this.bindPoseQuaternions[name]?.clone() ?? new THREE.Quaternion())
    }
  }

  private applyPlaceholderPose(poseName: string) {
    this.phTarget = { ...(PLACEHOLDER_POSES[poseName] ?? REST_PH) }
  }

  private applyKeypointPose(keypoints: Pose['keypoints']) {
    // 現在のボーン回転をトランジション開始点としてキャプチャ
    this.transitionSource = {}
    for (const { bone: boneName } of Object.values(MP_TO_BONE)) {
      const bone = this.findBone(boneName)
      if (bone) this.transitionSource[boneName] = bone.quaternion.clone()
    }
    this.targetRotations = {}
    this.transitionProgress = 0.0
    const pos: Record<string, THREE.Vector3> = {}
    for (const [name, kp] of Object.entries(keypoints)) {
      if ((kp.visibility ?? 1) > 0.3)
        pos[name] = new THREE.Vector3((kp.x - 0.5) * 2, (0.5 - kp.y) * 2, -(kp.z ?? 0) * 2)
    }
    for (const { bone: boneName, parent: p, child: c } of Object.values(MP_TO_BONE)) {
      if (!pos[p] || !pos[c]) continue
      const bone    = this.findBone(boneName); if (!bone) continue
      const restDir = BONE_REST_DIRS[boneName]; if (!restDir) continue
      const dir = pos[c].clone().sub(pos[p]).normalize()
      if (dir.lengthSq() < 0.001) continue
      const worldQ  = new THREE.Quaternion().setFromUnitVectors(restDir, dir)
      const parentQ = new THREE.Quaternion()
      if (bone.parent) (bone.parent as THREE.Bone).getWorldQuaternion(parentQ)
      this.targetRotations[boneName] = parentQ.clone().invert().multiply(worldQ)
    }
  }

  resetPose() {
    this.targetRotations = {}
    this.transitionSource = {}
    this.transitionProgress = 1.0
    for (const bone of Object.values(this.bones)) bone.quaternion.set(0, 0, 0, 1)
    this.phTarget = { ...REST_PH }
  }

  private easeInOut(t: number): number {
    return t < 0.5 ? 2 * t * t : -1 + (4 - 2 * t) * t
  }

  beatPulse() { this.beatScale = 1.018 }

  showPlaceholder() {
    if (this.model || this.placeholder) return
    const mat = new THREE.MeshStandardMaterial({ color: 0x4a4a8a, roughness: 0.6 })
    const g   = new THREE.Group()
    const add = (geo: THREE.BufferGeometry, x: number, y: number, z: number): THREE.Mesh => {
      const m = new THREE.Mesh(geo, mat)
      m.position.set(x, y, z); m.castShadow = true; g.add(m); return m
    }
    add(new THREE.SphereGeometry(0.12, 16, 12),           0,          1.70, 0)
    this.phTorso   = add(new THREE.CylinderGeometry(0.09, 0.11, 0.45, 8), 0, 1.35, 0)
    add(new THREE.CylinderGeometry(0.10, 0.09, 0.25, 8),  0,          0.99, 0)
    this.phLeftArm  = add(new THREE.CylinderGeometry(0.04, 0.04, 0.38, 8), REST_PH.lX, REST_PH.lY, 0)
    this.phRightArm = add(new THREE.CylinderGeometry(0.04, 0.04, 0.38, 8), REST_PH.rX, REST_PH.rY, 0)
    add(new THREE.CylinderGeometry(0.05, 0.04, 0.50, 8), -0.10,       0.65, 0)
    add(new THREE.CylinderGeometry(0.05, 0.04, 0.50, 8),  0.10,       0.65, 0)
    if (this.phLeftArm)  this.phLeftArm.rotation.z  = REST_PH.lZ
    if (this.phRightArm) this.phRightArm.rotation.z = REST_PH.rZ
    this.scene.add(g)
    this.placeholder = g
  }

  hidePlaceholder() {
    if (this.placeholder) { this.scene.remove(this.placeholder); this.placeholder = null }
    this.phLeftArm = null; this.phRightArm = null; this.phTorso = null
  }

  destroy() {
    cancelAnimationFrame(this.rafId)
    this.ro?.disconnect()
    window.removeEventListener('resize', () => this.resize())
    this.renderer.dispose()
    this.renderer.domElement.remove()
  }
}
