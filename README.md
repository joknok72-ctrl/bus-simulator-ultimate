# 🚌 Bus Simulator Ultimate — محاكي الباص المطلق

لعبة محاكاة قيادة باص للموبايل (Android — وضع عمودي، يد واحدة) مبنية بمحرك **Godot Engine 4.7.2-stable** بلغة **GDScript**.

> بُنيت على فلسفة: **"اصنع لعبة ممتعة في أبسط أشكالها أولاً، ثم ضع فوقها الجرافيك والصوت."**
> كل شيء في اللعبة (المدينة، الباصات، الأصوات، الواجهة) مولّد برمجياً — لا ملفات 3D أو صوتيات خارجية. الحجم صغير والأداء مناسب للهواتف المتوسطة.

## 📲 نزّل اللعبة على هاتفك الآن (APK جاهز)
[![Download APK](https://img.shields.io/badge/⬇_تنزيل_APK-Android-brightgreen?style=for-the-badge)](https://github.com/joknok72-ctrl/bus-simulator-ultimate/releases/download/latest/BusSimulatorUltimate.apk)
[![Build](https://github.com/joknok72-ctrl/bus-simulator-ultimate/actions/workflows/build-android.yml/badge.svg)](https://github.com/joknok72-ctrl/bus-simulator-ultimate/actions)

**الرابط المباشر**: https://github.com/joknok72-ctrl/bus-simulator-ultimate/releases/download/latest/BusSimulatorUltimate.apk

كل `push` على `main` يبني APK جديداً تلقائياً عبر GitHub Actions (Godot 4.7.2 + Android SDK) وينشره في [Releases](https://github.com/joknok72-ctrl/bus-simulator-ultimate/releases/tag/latest).
عند التثبيت فعّل "السماح بالتثبيت من مصادر غير معروفة".

## 🔗 الروابط
- **GitHub**: https://github.com/joknok72-ctrl/bus-simulator-ultimate
- **Releases (APK)**: https://github.com/joknok72-ctrl/bus-simulator-ultimate/releases/tag/latest
- **المحرك المطلوب**: Godot 4.7.2-stable (عادي، ليس .NET)

## 📱 الـ Stack المختار ولماذا
| العنصر | الاختيار | السبب |
|---|---|---|
| المحرك | Godot 4.7.2-stable | مفتوح المصدر، خفيف، تصدير Android مباشر، مناسب للموبايل |
| اللغة | GDScript (100%) | أسرع لغة تطوير داخل Godot، بدون تعقيدات بناء C#/C++ |
| الفيزياء | Jolt Physics (مدمج) | أسرع وأثبت من الفيزياء القديمة، مناسب للسيارات |
| الرندر | Mobile renderer + GL Compatibility fallback | أفضل أداء على الهواتف |
| الصوت | WAV مولّد بـ Python/NumPy (`tools/gen_audio.py`) | لا حقوق ملكية، حجم صغير |
| الحفظ | JSON في `user://save.json` | بسيط وآمن |

## 🎮 حلقة اللعب الأساسية (Core Loop)
```
تقود نحو المحطة ← تصطف بجانب الرصيف (Perfect/Good/OK) ← تفتح الأبواب
← ركاب ينزلون/يصعدون + مال فوري (+٥ ج) ← تغلق الأبواب ← المحطة التالية
← نهاية الخط: مكافأة + نجوم + XP ← الجراج: شراء باص/ترقية ← خط جديد
```

### ما الذي يجعلها ممتعة (Game Feel)
- **دقة الاصطفاف**: كل توقف تحدٍّ صغير له درجة ومكافأة فورية.
- **راحة الركاب**: فرملة مفاجئة أو انعطاف حاد يخفض الرضا ← تذاكر أقل. توتر ممتع بين "أسرع" و"أنعم".
- **إشارات المرور + سيارات AI**: عبور إشارة حمراء أو حادث = غرامة.
- **ردود فعل**: أضواء فرامل، هزّة كاميرا، اهتزاز الجهاز، صوت محرك يتبع السرعة، أرقام تطفو.

## ✅ الميزات المكتملة
- [x] فيزياء باص `VehicleBody3D` مع 4 باصات (ميني، مدينة، سياحي، مفصلي) بخصائص مختلفة
- [x] مدينة برمجية 5×5 تقاطعات، مبانٍ باستيل، أشجار، أعمدة إنارة، أرصفة بتصادم
- [x] 5 خطوط (نهار / ليل / مساء ممطر) بمحطات بأسماء عربية
- [x] محطات بركاب منتظرين، تقييم اصطفاف 3 درجات، سهم ولافتة للمحطة القادمة
- [x] 14 سيارة AI + إشارات مرور تعمل + كشف عبور الإشارة الحمراء
- [x] تحكم لمس بيد واحدة: عجلة قيادة دائرية، بنزين/فرامل، أبواب، كلاكس، كاميرا (3 أوضاع)
- [x] HUD: سرعة، حد السرعة، مال، محطة قادمة ومسافة، ركاب، رضا، خريطة صغيرة
- [x] اقتصاد: مال، XP، 12 مستوى، شراء باصات، 4 ترقيات متدرجة
- [x] قوائم كاملة: رئيسية، جراج/خطوط، إيقاف، نتائج (نجوم)، إعدادات
- [x] 15 مؤثراً صوتياً + موسيقى + جو مدينة — كلها مولّدة برمجياً
- [x] حفظ/تحميل تلقائي، إعادة تعيين التقدم
- [x] استقرار: مقاومة انقلاب + تعافٍ تلقائي + زر "إعادة للطريق"
- [x] وضع اختبار آلي (`--test`) يقود الباص ويأخذ لقطات شاشة للتحقق البصري
- [x] إعداد تصدير Android (`export_presets.cfg`)

## 🚧 غير مكتمل / أفكار للتطوير
- [ ] أصوات ركاب (شكر/شكوى) ونظام تعليقات
- [ ] مهام يومية وإنجازات
- [ ] تخصيص ألوان الباص وشعارات
- [ ] طقس ديناميكي أكثر (ثلج، ضباب)
- [ ] لوحة متصدرين محلية
- [ ] دعم وضع أفقي اختياري

## 📂 بنية المشروع
```
webapp/
├── project.godot            # إعدادات المشروع (Mobile renderer, Jolt, Portrait)
├── export_presets.cfg       # إعداد تصدير Android
├── icon.svg
├── scenes/Main.tscn         # المشهد الوحيد؛ كل شيء يُبنى برمجياً
├── scripts/
│   ├── Main.gd              # إدارة الحالات + كل القوائم + تدفق الاختبار
│   ├── autoload/
│   │   ├── GameState.gd     # المال/XP/الباصات/الترقيات/الحفظ
│   │   ├── AudioFX.gd       # مدير الصوت + المحرك + الموسيقى
│   │   └── Haptics.gd       # اهتزاز الجهاز
│   ├── data/
│   │   ├── BusData.gd       # مواصفات الباصات والترقيات
│   │   └── RouteData.gd     # الخطوط والمحطات
│   ├── world/
│   │   ├── DrivingScene.gd  # منسّق Core Loop + كاميرا + بيئة
│   │   ├── Bus.gd           # فيزياء الباص + جسمه + أبوابه + راحة الركاب
│   │   ├── BusStop.gd       # المحطة + تقييم الاصطفاف + الركاب
│   │   ├── CityBuilder.gd   # بناء المدينة (MultiMesh للأداء)
│   │   └── Traffic.gd       # سيارات AI + إشارات مرور
│   └── ui/
│       ├── TouchControls.gd # عجلة القيادة والأزرار (مرسومة برمجياً)
│       └── HUD.gd           # واجهة القيادة + الخريطة الصغيرة
├── audio/                   # 15 ملف WAV مولّد
├── tools/
│   ├── gen_audio.py         # مولّد الأصوات
│   └── run_test.sh          # تشغيل الاختبار الآلي بلقطات شاشة
└── docs/GDD.md              # وثيقة تصميم اللعبة
```

## 🕹️ التحكم
| موبايل | كيبورد (للاختبار على الكمبيوتر) |
|---|---|
| سحب العجلة يسار الشاشة | ← → أو A / D |
| ▲ بنزين | ↑ أو W |
| ▼ فرامل (وعند التوقف = رجوع للخلف) | ↓ أو S |
| 🚪 الأبواب | E أو Space |
| 📢 كلاكس | H |
| 📷 تغيير الكاميرا | C |
| II إيقاف | Esc أو P |

## 🛠️ التشغيل والبناء
### فتح المشروع
1. نزّل [Godot 4.7.2-stable](https://godotengine.org/download) (الإصدار العادي، ليس .NET).
2. Import → اختر `project.godot` → Run (F5).

### تصدير APK للأندرويد
1. في Godot: **Editor → Manage Export Templates → Download and Install** (نسخة 4.7.2).
2. ثبّت Android SDK + JDK 17 وحدد مساراتهم في **Editor Settings → Export → Android**.
3. أنشئ keystore للتصحيح (أو دع Godot ينشئه).
4. **Project → Export → Android → Export Project** → `build/BusSimulatorUltimate.apk`.

### اختبار آلي بلقطات شاشة (Linux)
```bash
python3 tools/gen_audio.py                 # إعادة توليد الأصوات (اختياري)
tools/run_test.sh menu,garage,settings,drive,pause,results 720x1280
tools/run_test.sh drive_long 360x640      # قيادة آلية طويلة
# اللقطات في /tmp/shots
```

## 🗄️ نموذج البيانات (الحفظ)
```json
{
  "money": 300, "xp": 0, "level": 1,
  "owned_buses": ["mini"], "current_bus": "mini",
  "upgrades": {"engine": 0, "brakes": 0, "suspension": 0, "seats": 0},
  "stats": {"passengers": 0, "routes": 0, "distance_km": 0, "perfect_stops": 0, "fines": 0, "earned": 0, "collisions": 0},
  "settings": {"sfx": 0.9, "music": 0.5, "haptics": true, "camera": 0, "shadows": true, "steer_sensitivity": 1.0},
  "route_records": {"line1": {"best": 0, "times": 0}},
  "selected_route": "line1"
}
```

## 📊 الحالة
- **المنصة المستهدفة**: Android (Portrait) — يعمل أيضاً على سطح المكتب للاختبار
- **المحرك**: Godot 4.7.2-stable (مثبّت حرفياً على هذا الإصدار)
- **آخر تحديث**: 2026-09-18
