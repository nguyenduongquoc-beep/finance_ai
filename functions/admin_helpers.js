const crypto = require("crypto");

const ALLOWED_CONFIG_TYPES = [
  "ai_runtime",
  "financial_heuristics",
  "transaction_rules",
];

// Danh mục Model ID hợp lệ theo tài liệu Gemini API chính thức
const SUPPORTED_GEMINI_MODELS = [
  "gemini-3.8-flash",
  "gemini-3.7-flash",
  "gemini-3.6-flash",
  "gemini-3.5-flash",
  "gemini-3.5-flash-lite",
  "gemini-3-flash-preview",
  "gemini-2.5-flash",
  "gemini-2.5-flash-lite",
  "gemini-2.5-pro",
  "gemini-flash-latest",
];

const MUTABLE_ALIAS_GEMINI_MODELS = ["gemini-flash-latest"];

const FORBIDDEN_SECRET_KEYS = [
  "apikey",
  "geminiapikey",
  "gemini_api_key",
  "api_key",
  "secret",
  "privatekey",
  "private_key",
  "secretsalt",
  "accesstoken",
];

const ALLOWED_KNOWLEDGE_TOPICS = [
  "budget_rule",
  "saving_strategy",
  "spending_control",
  "crisis_recovery",
];

const ALLOWED_KNOWLEDGE_TRIGGERS = [
  "always",
  "low_saving_rate",
  "essential_deficit",
  "variable_income",
  "budget_overrun",
  "infeasible_goal",
];

const CANONICAL_EXPENSE_GROUPS = [
  "di chuyen",
  "an uong",
  "mua sam",
  "hoa don",
  "suc khoe",
  "giai tri",
  "giao duc",
];

const CANONICAL_INCOME_GROUPS = ["luong", "thuong"];
const CANONICAL_WALLET_TYPES = ["cash", "eWallet", "bank"];

// Phải khớp 100% với TransactionIntelligenceService / kProtectedBuiltInExpenseKeywords ở Client
const PROTECTED_EXPENSE_KEYWORDS = {
  "di chuyen": [
    "grab",
    "be",
    "xanh sm",
    "gojek",
    "taxi",
    "xang",
    "xe bus",
    "ve xe",
    "gui xe",
    "bai xe",
    "di chuyen",
    "giao thong",
  ],
  "an uong": [
    "highlands",
    "starbucks",
    "ca phe",
    "pho",
    "com",
    "tra sua",
    "kfc",
    "mcdonalds",
    "lotte",
    "nha hang",
    "an sang",
    "an trua",
    "an toi",
    "banh mi",
    "nuoc ep",
    "tai xin",
    "quan an",
    "bun",
    "lau",
    "nuong",
    "tra",
    "banh",
    "food",
    "coffee",
    "sua da",
    "bac xiu",
    "matcha",
    "sinh to",
  ],
  "mua sam": [
    "shopee",
    "lazada",
    "tiki",
    "sieu thi",
    "quan ao",
    "giay",
    "bach hoa xanh",
    "winmart",
    "circle k",
    "7-eleven",
    "mua sam",
    "thoi trang",
    "my pham",
    "shopping",
  ],
  "hoa don": [
    "dien",
    "nuoc",
    "internet",
    "wifi",
    "truyen hinh",
    "tien dien",
    "tien nuoc",
    "tien nha",
    "rac",
    "hoa don",
    "dich vu",
    "bill",
  ],
  "suc khoe": [
    "thuoc",
    "nha thuoc",
    "benh vien",
    "phong kham",
    "kham benh",
    "pharmedic",
    "pharmacity",
    "long chau",
    "y te",
    "suc khoe",
  ],
  "giai tri": [
    "xem phim",
    "cgv",
    "lotte cinema",
    "du lich",
    "game",
    "ve xem phim",
    "giai tri",
    "cinema",
    "movie",
  ],
  "giao duc": [
    "hoc phi",
    "sach",
    "khoa hoc",
    "giao duc",
    "truong hoc",
    "hoc tap",
    "hoc tieng anh",
  ],
};

// Phải khớp 100% với TransactionIntelligenceService / kProtectedBuiltInIncomeKeywords ở Client
const PROTECTED_INCOME_KEYWORDS = {
  thuong: ["thuong", "tien thuong", "bonus", "khen thuong", "thuong tet"],
  luong: [
    "luong",
    "thuong",
    "income",
    "salary",
    "tien luong",
    "tien thuong",
    "freelance",
    "hoa hong",
    "ban hang",
    "doanh thu",
    "thu nhap",
    "bonus",
  ],
};

// Khóa nhà cung cấp thanh toán mặc định hệ thống được bảo vệ (chỉ đọc, không cho phép ghi đè)
const PROTECTED_PAYMENT_PROVIDER_KEYS = [
  "cash",
  "momo",
  "zalopay",
  "shopeepay",
  "vnpay",
  "viettel_money",
  "apple_pay",
  "google_pay",
  "samsung_pay",
  "mbbank",
  "vietcombank",
  "techcombank",
  "vietinbank",
  "bidv",
  "agribank",
  "acb",
  "tpbank",
  "vpbank",
  "sacombank",
  "vib",
  "hdbank",
  "shb",
  "msb",
  "ocb",
  "seabank",
  "lpbank",
  "eximbank",
  "cake",
  "timo",
  "generic_bank",
  "generic_ewallet",
];

// Toàn bộ ngưỡng định lượng FinancialHeuristicsConfig - khớp 1:1 với Dart client
const FINANCIAL_HEURISTICS_RANGES = [
  { key: "categorySpikeRatio", label: "Ngưỡng đột biến danh mục", min: 0.15, max: 0.6, integer: false },
  { key: "categoryIncomeShareThreshold", label: "Ngưỡng tỷ trọng danh mục/thu nhập", min: 0.15, max: 0.5, integer: false },
  { key: "minRecommendedSavingRate", label: "Tỷ lệ tiết kiệm khuyến nghị", min: 0.05, max: 0.4, integer: false },
  { key: "incomeDropWarningRatio", label: "Ngưỡng cảnh báo sụt giảm thu nhập", min: 0.1, max: 0.4, integer: false },
  { key: "incomeDropCriticalRatio", label: "Ngưỡng nghiêm trọng sụt giảm thu nhập", min: 0.25, max: 0.7, integer: false },
  { key: "defaultSavingRateNoGoal", label: "Tỷ lệ tiết kiệm mặc định khi chưa có mục tiêu", min: 0.05, max: 0.35, integer: false },
  { key: "flexibleSpendFloorRatio", label: "Ngưỡng sàn chi tiêu linh hoạt", min: 0.5, max: 0.85, integer: false },
  { key: "planBudgetAdherenceWeight", label: "Trọng số điểm tuân thủ ngân sách", min: 0.4, max: 0.8, integer: false },
  { key: "budgetNearLimitRatio", label: "Ngưỡng cảnh báo sắp vượt ngân sách", min: 0.7, max: 0.95, integer: false },
  { key: "categoryForecastWarningRatio", label: "Ngưỡng cảnh báo dự báo danh mục tháng", min: 1.15, max: 1.6, integer: false },
  { key: "categoryForecastCriticalRatio", label: "Ngưỡng nghiêm trọng dự báo danh mục tháng", min: 1.4, max: 2.5, integer: false },
  { key: "categoryForecastMinDiffVnd", label: "Chênh lệch tối thiểu cảnh báo dự báo danh mục", min: 50000, max: 500000, integer: false },
  { key: "healthNegativeBalancePenalty", label: "Điểm trừ số dư dự báo âm", min: 10, max: 40, integer: true },
  { key: "healthBudgetExceededPenalty", label: "Điểm trừ ngân sách vượt hạn mức", min: 5, max: 25, integer: true },
  { key: "healthBudgetAtRiskPenalty", label: "Điểm trừ ngân sách có nguy cơ vượt", min: 5, max: 20, integer: true },
  { key: "txAnomalyMinDiffVnd", label: "Chênh lệch tối thiểu giao dịch bất thường", min: 50000, max: 500000, integer: false },
  { key: "txAnomalyWarningMultiplier", label: "Hệ số cảnh báo giao dịch lẻ bất thường", min: 1.5, max: 3.5, integer: false },
  { key: "txAnomalyCriticalMultiplier", label: "Hệ số nghiêm trọng giao dịch lẻ bất thường", min: 3.0, max: 6.0, integer: false },
];

function createHttpError(statusCode, message, extra = {}) {
  const err = new Error(message);
  err.statusCode = statusCode;
  Object.assign(err, extra);
  return err;
}

function sendErrorResponse(res, error, fallbackMessage) {
  const code = error && error.statusCode ? error.statusCode : 500;
  const body = {
    error: (error && error.message) || fallbackMessage || "Lỗi xử lý phía máy chủ.",
  };
  if (error && Array.isArray(error.validationErrors) && error.validationErrors.length > 0) {
    body.validationErrors = error.validationErrors;
  }
  res.status(code).json(body);
}

function normalizeVietnameseKeyword(input) {
  let str = String(input ?? "").toLowerCase().trim();
  const vietnameseSigns = [
    "aàáạảãâầấậẩẫăằắặẳẵ",
    "eèéẹẻẽêềếệểễ",
    "iìíịỉĩ",
    "oòóọỏõôồốộổỗơờớợởỡ",
    "uùúụủũưừứựửữ",
    "yỳýỵỷỹ",
    "dđ",
  ];
  // Chuẩn hóa Unicode NFD phòng trường hợp dấu tổ hợp từ bàn phím Web/macOS
  str = str.normalize("NFC");
  for (let i = 0; i < vietnameseSigns.length; i++) {
    const group = vietnameseSigns[i];
    for (let j = 1; j < group.length; j++) {
      str = str.split(group[j]).join(group[0]);
    }
  }
  return str.replace(/\s+/g, " ").trim();
}

function containsForbiddenSecretField(obj) {
  if (!obj || typeof obj !== "object") return false;
  if (Array.isArray(obj)) {
    return obj.some(containsForbiddenSecretField);
  }
  for (const key of Object.keys(obj)) {
    const lower = key.toLowerCase();
    if (FORBIDDEN_SECRET_KEYS.includes(lower)) {
      return true;
    }
    if (containsForbiddenSecretField(obj[key])) {
      return true;
    }
  }
  return false;
}

function canonicalizeJsonValue(value) {
  if (
    value === null ||
    value === undefined ||
    typeof value === "boolean" ||
    typeof value === "string"
  ) {
    return value === undefined ? null : value;
  }
  if (typeof value === "number") {
    if (Number.isInteger(value)) return value;
    const rounded = Number(value.toFixed(6));
    return Number.isInteger(rounded) ? Math.trunc(rounded) : rounded;
  }
  if (Array.isArray(value)) {
    return value.map(canonicalizeJsonValue);
  }
  if (typeof value === "object") {
    const sortedKeys = Object.keys(value).sort();
    const result = {};
    for (const k of sortedKeys) {
      result[k] = canonicalizeJsonValue(value[k]);
    }
    return result;
  }
  return String(value);
}

function computeCanonicalConfigHash(payload) {
  const canonicalJson = JSON.stringify(canonicalizeJsonValue(payload || {}));
  return crypto.createHash("sha256").update(canonicalJson, "utf8").digest("hex");
}

function _validateKeywordMapServerSide({
  rawMap,
  sectionLabel,
  allowedGroups,
  protectedBuiltInMap,
  errors,
}) {
  if (rawMap === undefined) return;
  if (!rawMap || typeof rawMap !== "object" || Array.isArray(rawMap)) {
    errors.push(`${sectionLabel} phải là đối tượng ánh xạ từ nhóm chuẩn sang danh sách từ khóa.`);
    return;
  }

  // Lập bảng từ khóa built-in được bảo vệ (mỗi từ khóa có thể xuất hiện ở 1 hoặc nhiều nhóm hệ thống)
  const builtInGroupsByKeyword = new Map();
  for (const g of allowedGroups) {
    const kws = protectedBuiltInMap[g] || [];
    for (const kw of kws) {
      const norm = normalizeVietnameseKeyword(kw);
      if (!norm) continue;
      if (!builtInGroupsByKeyword.has(norm)) {
        builtInGroupsByKeyword.set(norm, new Set());
      }
      builtInGroupsByKeyword.get(norm).add(g);
    }
  }

  const adminGroupByKeyword = new Map();

  for (const [rawGroupKey, rawList] of Object.entries(rawMap)) {
    const groupKey = normalizeVietnameseKeyword(rawGroupKey);
    if (!allowedGroups.includes(groupKey)) {
      errors.push(
        `Nhóm ngữ nghĩa "${rawGroupKey}" trong ${sectionLabel} không thuộc nhóm chuẩn hệ thống.`
      );
      continue;
    }
    if (!Array.isArray(rawList)) {
      errors.push(`Danh sách từ khóa của nhóm "${groupKey}" phải là mảng.`);
      continue;
    }

    const seenInGroup = new Set();
    for (const item of rawList) {
      if (typeof item !== "string") {
        errors.push(`Từ khóa trong nhóm "${groupKey}" phải là chuỗi ký tự.`);
        continue;
      }
      const normKw = normalizeVietnameseKeyword(item);
      if (normKw.length < 2 || normKw.length > 60) {
        errors.push(`Từ khóa "${item}" trong nhóm "${groupKey}" phải dài từ 2 đến 60 ký tự.`);
        continue;
      }

      if (seenInGroup.has(normKw)) {
        errors.push(`Từ khóa "${normKw}" bị trùng lặp trong cùng nhóm "${groupKey}".`);
        continue;
      }
      seenInGroup.add(normKw);

      // Kiểm tra bảo vệ built-in bất kể danh sách disable nào (built-in là bất biến)
      const builtInGroups = builtInGroupsByKeyword.get(normKw);
      if (builtInGroups && builtInGroups.size > 0) {
        if (builtInGroups.has(groupKey)) {
          errors.push(
            `Từ khóa "${normKw}" đã tồn tại trong từ điển mặc định hệ thống của nhóm "${groupKey}".`
          );
        } else {
          const otherGroup = Array.from(builtInGroups)[0];
          errors.push(
            `Xung đột với từ khóa mặc định được bảo vệ: "${normKw}" đang thuộc nhóm "${otherGroup}".`
          );
        }
        continue;
      }

      const prevAdminGroup = adminGroupByKeyword.get(normKw);
      if (prevAdminGroup && prevAdminGroup !== groupKey) {
        errors.push(
          `Xung đột từ khóa bổ sung giữa hai nhóm "${prevAdminGroup}" và "${groupKey}" cho từ "${normKw}".`
        );
        continue;
      }
      adminGroupByKeyword.set(normKw, groupKey);
    }
  }
}

function validateConfigPayloadServerSide(configType, payload) {
  if (!payload || typeof payload !== "object" || Array.isArray(payload)) {
    return ["Payload cấu hình không hợp lệ hoặc bị rỗng."];
  }
  const errors = [];

  if (containsForbiddenSecretField(payload)) {
    errors.push("Tuyệt đối không được đưa API Key hoặc khóa bí mật vào cấu hình động.");
  }

  if (configType === "ai_runtime") {
    const primary = String(payload.primaryModel || "").trim();
    if (!SUPPORTED_GEMINI_MODELS.includes(primary)) {
      errors.push(`Model chính "${primary}" không nằm trong danh sách Whitelist hỗ trợ.`);
    }
    if (MUTABLE_ALIAS_GEMINI_MODELS.includes(primary)) {
      errors.push(`Không được chọn alias động "${primary}" làm model chính.`);
    }
    if (Array.isArray(payload.fallbackModels)) {
      const cleanFallbacks = [];
      for (const fb of payload.fallbackModels) {
        const fbStr = String(fb || "").trim();
        if (!SUPPORTED_GEMINI_MODELS.includes(fbStr)) {
          errors.push(`Model dự phòng "${fbStr}" không nằm trong danh sách Whitelist.`);
        } else {
          cleanFallbacks.push(fbStr);
        }
      }
      const nonAliasFallbacks = cleanFallbacks.filter(
        (m) => !MUTABLE_ALIAS_GEMINI_MODELS.includes(m)
      );
      if (cleanFallbacks.length > 0 && nonAliasFallbacks.length === 0) {
        errors.push(
          "Không được chỉ sử dụng alias động (gemini-flash-latest) làm cơ chế fallback duy nhất."
        );
      }
    } else if (payload.fallbackModels !== undefined) {
      errors.push("fallbackModels phải là danh sách chuỗi.");
    }
    const temp = Number(payload.temperature);
    if (payload.temperature === undefined || payload.temperature === null || Number.isNaN(temp) || temp < 0.1 || temp > 0.8) {
      errors.push("Temperature phải nằm trong khoảng 0.1 đến 0.8.");
    }
    const maxHist = Number(payload.maxChatHistoryMessages);
    if (
      payload.maxChatHistoryMessages === undefined ||
      payload.maxChatHistoryMessages === null ||
      Number.isNaN(maxHist) ||
      !Number.isInteger(maxHist) ||
      maxHist < 4 ||
      maxHist > 20
    ) {
      errors.push("Số tin nhắn lịch sử hội thoại phải là số nguyên từ 4 đến 20.");
    }
    if (payload.prompts !== undefined) {
      if (!payload.prompts || typeof payload.prompts !== "object" || Array.isArray(payload.prompts)) {
        errors.push("prompts phải là một đối tượng key-value hợp lệ.");
      } else {
        for (const [k, v] of Object.entries(payload.prompts)) {
          if (typeof v !== "string" || v.trim().length === 0) {
            errors.push(`Prompt "${k}" không được để trống.`);
          } else if (v.trim().length > 4000) {
            errors.push(`Prompt "${k}" vượt quá giới hạn 4000 ký tự.`);
          }
        }
      }
    }
  } else if (configType === "financial_heuristics") {
    for (const spec of FINANCIAL_HEURISTICS_RANGES) {
      const rawVal = payload[spec.key];
      const numVal = typeof rawVal === "number" ? rawVal : Number(rawVal);
      if (
        rawVal === undefined ||
        rawVal === null ||
        typeof rawVal === "boolean" ||
        Number.isNaN(numVal) ||
        !Number.isFinite(numVal) ||
        numVal < spec.min ||
        numVal > spec.max
      ) {
        errors.push(`${spec.label} (${spec.key}) phải nằm trong khoảng ${spec.min} đến ${spec.max}.`);
      } else if (spec.integer && !Number.isInteger(numVal)) {
        errors.push(`${spec.label} (${spec.key}) phải là số nguyên.`);
      }
    }

    const minRec = Number(payload.minRecommendedSavingRate);
    const defSav = Number(payload.defaultSavingRateNoGoal);
    if (Number.isFinite(minRec) && Number.isFinite(defSav) && defSav > minRec + 1e-9) {
      errors.push(
        `Tỷ lệ tiết kiệm mặc định khi chưa có mục tiêu (${defSav}) không được lớn hơn tỷ lệ tiết kiệm khuyến nghị (${minRec}).`
      );
    }

    const incWarn = Number(payload.incomeDropWarningRatio);
    const incCrit = Number(payload.incomeDropCriticalRatio);
    if (Number.isFinite(incWarn) && Number.isFinite(incCrit) && incCrit + 1e-9 < incWarn + 0.1) {
      errors.push(
        `Ngưỡng sụt giảm thu nhập nghiêm trọng (${incCrit}) phải lớn hơn ngưỡng cảnh báo (${incWarn}) ít nhất 0.10.`
      );
    }

    const catWarn = Number(payload.categoryForecastWarningRatio);
    const catCrit = Number(payload.categoryForecastCriticalRatio);
    if (Number.isFinite(catWarn) && Number.isFinite(catCrit) && catCrit + 1e-9 < catWarn + 0.15) {
      errors.push(
        `Ngưỡng dự báo nghiêm trọng (${catCrit}) phải lớn hơn ngưỡng cảnh báo (${catWarn}) ít nhất 0.15.`
      );
    }

    const txWarn = Number(payload.txAnomalyWarningMultiplier);
    const txCrit = Number(payload.txAnomalyCriticalMultiplier);
    if (Number.isFinite(txWarn) && Number.isFinite(txCrit) && txCrit + 1e-9 < txWarn + 1.0) {
      errors.push(
        `Hệ số giao dịch bất thường nghiêm trọng (${txCrit}) phải lớn hơn hệ số cảnh báo (${txWarn}) ít nhất 1.0x.`
      );
    }
  } else if (configType === "transaction_rules") {
    // 1. Không cho phép vô hiệu hóa bất kỳ built-in keyword nào đã khóa cứng bảo vệ
    if (payload.disabledBuiltInKeywords !== undefined) {
      if (!Array.isArray(payload.disabledBuiltInKeywords)) {
        errors.push("disabledBuiltInKeywords phải là mảng.");
      } else if (payload.disabledBuiltInKeywords.length > 0) {
        errors.push(
          "Không được phép vô hiệu hóa từ khóa mặc định hệ thống (Built-in Keywords là quy tắc lõi chỉ đọc)."
        );
      }
    }

    // 2. Kiểm tra danh sách bật/tắt riêng cho từ khóa Admin bổ sung (nếu có)
    if (payload.disabledAdminKeywords !== undefined) {
      if (!Array.isArray(payload.disabledAdminKeywords)) {
        errors.push("disabledAdminKeywords phải là mảng chuỗi.");
      } else {
        for (const item of payload.disabledAdminKeywords) {
          const norm = normalizeVietnameseKeyword(item);
          if (typeof item !== "string" || norm.length < 2 || norm.length > 60) {
            errors.push(`disabledAdminKeywords chứa phần tử không hợp lệ: "${item}".`);
          }
        }
      }
    }

    // 3. Kiểm tra trùng lặp/xung đột từ khóa chi tiêu & thu nhập không dấu
    _validateKeywordMapServerSide({
      rawMap: payload.addedExpenseKeywords,
      sectionLabel: "addedExpenseKeywords",
      allowedGroups: CANONICAL_EXPENSE_GROUPS,
      protectedBuiltInMap: PROTECTED_EXPENSE_KEYWORDS,
      errors,
    });
    _validateKeywordMapServerSide({
      rawMap: payload.addedIncomeKeywords,
      sectionLabel: "addedIncomeKeywords",
      allowedGroups: CANONICAL_INCOME_GROUPS,
      protectedBuiltInMap: PROTECTED_INCOME_KEYWORDS,
      errors,
    });

    // 4. Kiểm tra nhà cung cấp thanh toán mở rộng cho OCR
    if (payload.customPaymentProviders !== undefined) {
      if (!Array.isArray(payload.customPaymentProviders)) {
        errors.push("customPaymentProviders phải là một danh sách.");
      } else {
        const seenProviderKeys = new Set();
        for (const provider of payload.customPaymentProviders) {
          if (!provider || typeof provider !== "object" || Array.isArray(provider)) {
            errors.push("Mỗi mục trong customPaymentProviders phải là đối tượng hợp lệ.");
            continue;
          }
          const rawKey = String(provider.key || "");
          const key = normalizeVietnameseKeyword(rawKey).replace(/\s+/g, "_");
          if (!/^[a-z0-9_]{2,40}$/.test(key)) {
            errors.push(`Mã nhà cung cấp thanh toán "${rawKey}" phải gồm 2-40 ký tự a-z, 0-9 hoặc _.`);
          } else if (PROTECTED_PAYMENT_PROVIDER_KEYS.includes(key)) {
            errors.push(
              `Không được phép ghi đè nhà cung cấp thanh toán mặc định được bảo vệ: "${key}".`
            );
          } else if (seenProviderKeys.has(key)) {
            errors.push(`Mã nhà cung cấp thanh toán "${key}" bị trùng lặp trong cấu hình.`);
          } else {
            seenProviderKeys.add(key);
          }

          const label = String(provider.displayLabel || "").trim();
          if (label.length < 2 || label.length > 60) {
            errors.push(`Tên hiển thị nhà cung cấp "${key || rawKey}" phải dài từ 2 đến 60 ký tự.`);
          }

          if (!CANONICAL_WALLET_TYPES.includes(provider.walletType)) {
            errors.push(
              `walletType "${provider.walletType}" của nhà cung cấp "${key || label}" không hợp lệ (chỉ nhận cash, eWallet, bank).`
            );
          }

          if (provider.isActive !== undefined && typeof provider.isActive !== "boolean") {
            errors.push(`Trường isActive của nhà cung cấp "${key || label}" phải là kiểu boolean.`);
          }

          if (!Array.isArray(provider.receiptKeywords) || provider.receiptKeywords.length === 0) {
            errors.push(`Nhà cung cấp "${key || label}" phải có ít nhất 1 receiptKeywords.`);
          } else {
            for (const kw of provider.receiptKeywords) {
              const normKw = normalizeVietnameseKeyword(kw);
              if (typeof kw !== "string" || normKw.length < 2 || normKw.length > 60) {
                errors.push(`receiptKeywords của "${key || label}" chứa từ khóa không hợp lệ: "${kw}".`);
              }
            }
          }

          if (provider.walletNameAliases !== undefined) {
            if (!Array.isArray(provider.walletNameAliases)) {
              errors.push(`walletNameAliases của "${key || label}" phải là danh sách chuỗi.`);
            } else {
              for (const alias of provider.walletNameAliases) {
                const normAlias = normalizeVietnameseKeyword(alias);
                if (typeof alias !== "string" || normAlias.length < 2 || normAlias.length > 60) {
                  errors.push(`walletNameAliases của "${key || label}" chứa tên gọi không hợp lệ: "${alias}".`);
                }
              }
            }
          }
        }
      }
    }
  } else {
    errors.push(`Loại cấu hình "${configType}" không được hỗ trợ.`);
  }

  return errors;
}

function validateKnowledgeArticleServerSide(article, expectedArticleId) {
  if (!article || typeof article !== "object" || Array.isArray(article)) {
    return ["Dữ liệu bài viết tri thức không hợp lệ hoặc bị rỗng."];
  }
  const errors = [];

  if (containsForbiddenSecretField(article)) {
    errors.push("Tuyệt đối không được chứa API Key hoặc khóa bí mật trong bài viết tri thức.");
  }

  const articleId = String(article.articleId || "").trim();
  if (!/^[a-zA-Z0-9_-]{3,80}$/.test(articleId)) {
    errors.push("articleId phải dài 3-80 ký tự và chỉ gồm chữ cái, số, '_' hoặc '-'.");
  } else if (expectedArticleId && articleId !== expectedArticleId) {
    errors.push(`articleId "${articleId}" không khớp với document ID "${expectedArticleId}".`);
  }

  const title = String(article.title || "").trim();
  if (title.length < 3 || title.length > 120) {
    errors.push("Tiêu đề bài viết (title) phải dài từ 3 đến 120 ký tự.");
  }

  const topic = String(article.topic || "").trim();
  if (!ALLOWED_KNOWLEDGE_TOPICS.includes(topic)) {
    errors.push(
      `Chủ đề (topic) "${topic}" không hợp lệ. Chỉ chấp nhận: ${ALLOWED_KNOWLEDGE_TOPICS.join(", ")}.`
    );
  }

  const triggerCondition = String(article.triggerCondition || "").trim();
  if (!ALLOWED_KNOWLEDGE_TRIGGERS.includes(triggerCondition)) {
    errors.push(
      `Điều kiện kích hoạt (triggerCondition) "${triggerCondition}" không hợp lệ. Chỉ chấp nhận: ${ALLOWED_KNOWLEDGE_TRIGGERS.join(", ")}.`
    );
  }

  const priorityRaw = article.priority;
  const priority = Number(priorityRaw);
  if (
    priorityRaw === undefined ||
    priorityRaw === null ||
    typeof priorityRaw === "boolean" ||
    !Number.isInteger(priority) ||
    priority < 1 ||
    priority > 10
  ) {
    errors.push("Độ ưu tiên (priority) phải là số nguyên từ 1 đến 10.");
  }

  const summary = String(article.summaryForUser || "").trim();
  if (summary.length === 0 || summary.length > 250) {
    errors.push("Tóm tắt cho người dùng (summaryForUser) bắt buộc nhập và tối đa 250 ký tự.");
  }

  const snippet = String(article.aiGroundingSnippet || "").trim();
  if (snippet.length === 0 || snippet.length > 300) {
    errors.push("Đoạn tri thức tiêm vào AI (aiGroundingSnippet) bắt buộc nhập và tối đa 300 ký tự.");
  }

  if (article.suggestedPrompts !== undefined) {
    if (!Array.isArray(article.suggestedPrompts)) {
      errors.push("suggestedPrompts phải là mảng chuỗi.");
    } else if (article.suggestedPrompts.length > 3) {
      errors.push("suggestedPrompts tối đa chỉ được chứa 3 câu gợi ý.");
    } else {
      for (const p of article.suggestedPrompts) {
        if (typeof p !== "string" || p.trim().length === 0 || p.trim().length > 120) {
          errors.push("Mỗi câu gợi ý trong suggestedPrompts phải từ 1 đến 120 ký tự.");
        }
      }
    }
  }

  const rawActive = article.isActive !== undefined ? article.isActive : article.enabled;
  if (rawActive !== undefined && typeof rawActive !== "boolean") {
    errors.push("Trường trạng thái isActive/enabled phải là kiểu boolean (true/false).");
  }

  return errors;
}

/**
 * Xác thực Firebase ID Token + hồ sơ Firestore ở Backend.
 * Bảo toàn toàn bộ Custom Claims sẵn có khi tự động đồng bộ `{ admin: true }`.
 */
async function verifyAdminCallerWithDeps({
  req,
  db,
  auth,
  verifyAppCheckFn = async () => {},
  logger = console,
}) {
  await verifyAppCheckFn(req);
  const authHeader = (req && req.headers && req.headers.authorization) || "";
  if (!authHeader.startsWith("Bearer ")) {
    throw createHttpError(401, "Thiếu Firebase ID Token xác thực.");
  }

  const idToken = authHeader.substring("Bearer ".length).trim();
  if (!idToken) {
    throw createHttpError(401, "Firebase ID Token bị rỗng.");
  }

  let decoded;
  try {
    decoded = await auth.verifyIdToken(idToken, true);
  } catch (e) {
    throw createHttpError(401, "Phiên đăng nhập không hợp lệ hoặc đã hết hạn.");
  }

  const adminUserDoc = await db.collection("users").doc(decoded.uid).get();
  const userData = adminUserDoc.exists ? adminUserDoc.data() || {} : {};

  if (userData.status === "locked") {
    throw createHttpError(403, "Tài khoản quản trị viên này đã bị khóa.");
  }

  const hasClaim = decoded.admin === true;
  const hasFirestoreRole = userData.role === "admin";

  if (!hasClaim && !hasFirestoreRole) {
    throw createHttpError(
      403,
      "Truy cập bị từ chối: Tài khoản không có quyền Quản trị viên (Admin)."
    );
  }

  // Bảo toàn Custom Claims cũ khi đồng bộ claim admin=true từ Firestore role
  let claimsSynced = false;
  if (!hasClaim && hasFirestoreRole) {
    try {
      const userRecord = await auth.getUser(decoded.uid);
      const mergedClaims = {
        ...(userRecord && userRecord.customClaims ? userRecord.customClaims : {}),
        admin: true,
      };
      await auth.setCustomUserClaims(decoded.uid, mergedClaims);
      claimsSynced = true;
    } catch (claimErr) {
      if (logger && typeof logger.warn === "function") {
        logger.warn("Không thể đồng bộ Custom Claim tự động:", claimErr);
      }
    }
  }

  return {
    uid: decoded.uid,
    email: decoded.email || userData.email || "",
    name: userData.name || decoded.name || "",
    role: userData.role || (hasClaim ? "admin" : "user"),
    status: userData.status || "active",
    hasAdminClaim: hasClaim || claimsSynced,
    hasFirestoreRole: hasFirestoreRole,
    claimsSynced: claimsSynced,
  };
}

function createAdminEndpointHandlers({
  db,
  auth,
  fetchImpl = typeof fetch === "function" ? fetch : null,
  geminiApiKeyGetter = async () => process.env.GEMINI_API_KEY || "",
  verifyAppCheckFn = async () => {},
  logger = console,
  sandboxRateLimiter = new Map(),
  sandboxRateLimitWindowMs = 60000,
  sandboxRateLimitMaxCalls = 12,
  sandboxTimeoutMs = 15000,
  nowProvider = () => Date.now(),
}) {
  const verifyCaller = (req) =>
    verifyAdminCallerWithDeps({
      req,
      db,
      auth,
      verifyAppCheckFn,
      logger,
    });

  async function adminVerifySession(req, res) {
    if (req.method !== "GET" && req.method !== "POST") {
      res.status(405).json({ error: "Method Not Allowed" });
      return;
    }
    try {
      const caller = await verifyCaller(req);
      res.status(200).json({
        success: true,
        verifiedByServer: true,
        uid: caller.uid,
        email: caller.email,
        name: caller.name,
        role: caller.role,
        status: caller.status,
        hasAdminClaim: caller.hasAdminClaim,
        hasFirestoreRole: caller.hasFirestoreRole,
        claimsSynced: caller.claimsSynced,
      });
    } catch (error) {
      if (logger && typeof logger.error === "function") {
        logger.error("Lỗi adminVerifySession:", error.message || error);
      }
      sendErrorResponse(res, error, "Không thể xác minh phiên Quản trị viên.");
    }
  }

  async function adminSetUserRole(req, res) {
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method Not Allowed" });
      return;
    }
    try {
      const caller = await verifyCaller(req);
      const { targetUid, role } = req.body || {};

      if (!targetUid || (role !== "user" && role !== "admin")) {
        throw createHttpError(400, "Tham số targetUid hoặc role không hợp lệ.");
      }

      if (targetUid === caller.uid && role !== "admin") {
        throw createHttpError(400, "Không thể tự thu hồi quyền Admin của chính mình.");
      }

      const isAdminRole = role === "admin";
      const targetDocRef = db.collection("users").doc(targetUid);
      const targetSnap = await targetDocRef.get();
      const targetEmail = targetSnap.exists ? targetSnap.data().email || targetUid : targetUid;

      // 1. Cập nhật Custom Claims NHƯNG luôn bảo toàn các claims khác hiện có trên tài khoản
      const existingUser = await auth.getUser(targetUid);
      const mergedClaims = {
        ...(existingUser && existingUser.customClaims ? existingUser.customClaims : {}),
        admin: isAdminRole,
      };
      await auth.setCustomUserClaims(targetUid, mergedClaims);

      // 2. Đồng bộ role trên Firestore
      const nowIso = new Date(nowProvider()).toISOString();
      await targetDocRef.set(
        {
          role: role,
          updatedAt: nowIso,
        },
        { merge: true }
      );

      // 3. Ghi nhật ký quản trị
      const logRef = await db.collection("admin_logs").add({
        adminId: caller.uid,
        adminEmail: caller.email,
        action: "SET_USER_ROLE",
        targetType: "user",
        targetId: targetUid,
        targetLabel: targetEmail,
        result: "success",
        details: `Cập nhật quyền tài khoản ${targetEmail} thành ${role.toUpperCase()} (Custom Claim admin=${isAdminRole}).`,
        source: "cloud_function",
        createdAt: nowIso,
      });

      res.status(200).json({
        success: true,
        targetUid: targetUid,
        role: role,
        logId: logRef.id,
        message: `Đã cập nhật quyền ${targetEmail} thành ${role.toUpperCase()}.`,
      });
    } catch (error) {
      if (logger && typeof logger.error === "function") {
        logger.error("Lỗi adminSetUserRole:", error.message || error);
      }
      sendErrorResponse(res, error, "Không thể cập nhật quyền tài khoản.");
    }
  }

  async function adminPublishKnowledgeBase(req, res) {
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method Not Allowed" });
      return;
    }
    try {
      const caller = await verifyCaller(req);
      const {
        articleId,
        action = "publish",
        isActive,
        changeNote = "",
      } = req.body || {};

      const cleanId = String(articleId || "").trim();
      if (!cleanId) {
        throw createHttpError(400, "Thiếu articleId để xuất bản bài viết tri thức.");
      }
      if (action !== "publish" && action !== "toggle_active") {
        throw createHttpError(400, 'Tham số action chỉ hỗ trợ "publish" hoặc "toggle_active".');
      }
      if (action === "toggle_active" && typeof isActive !== "boolean") {
        throw createHttpError(400, "Trạng thái isActive (boolean) là bắt buộc khi toggle_active.");
      }

      const draftRef = db.collection("financial_knowledge_drafts").doc(cleanId);
      const pubRef = db.collection("financial_knowledge_published").doc(cleanId);
      const nowIso = new Date(nowProvider()).toISOString();

      let responseData = null;

      await db.runTransaction(async (tx) => {
        const [draftSnap, pubSnap] = await Promise.all([tx.get(draftRef), tx.get(pubRef)]);

        let sourceData;
        if (action === "publish") {
          if (!draftSnap.exists) {
            throw createHttpError(
              404,
              `Không tìm thấy bản nháp tri thức "${cleanId}" trong financial_knowledge_drafts.`
            );
          }
          sourceData = { ...(draftSnap.data() || {}) };
        } else {
          if (pubSnap.exists) {
            sourceData = { ...(pubSnap.data() || {}) };
          } else if (draftSnap.exists) {
            sourceData = { ...(draftSnap.data() || {}) };
          } else {
            throw createHttpError(404, `Không tìm thấy bài viết tri thức "${cleanId}".`);
          }
        }

        const effectiveActive =
          typeof isActive === "boolean"
            ? isActive
            : sourceData.isActive !== undefined
              ? sourceData.isActive
              : sourceData.enabled !== undefined
                ? sourceData.enabled
                : true;

        const normalizedPayload = {
          articleId: sourceData.articleId || cleanId,
          title: String(sourceData.title || "").trim(),
          topic: String(sourceData.topic || "").trim(),
          triggerCondition: String(sourceData.triggerCondition || "").trim(),
          priority: sourceData.priority,
          summaryForUser: String(sourceData.summaryForUser || "").trim(),
          aiGroundingSnippet: String(sourceData.aiGroundingSnippet || "").trim(),
          suggestedPrompts: Array.isArray(sourceData.suggestedPrompts)
            ? sourceData.suggestedPrompts.map((s) => String(s).trim())
            : [],
          isActive: effectiveActive,
        };

        const validationErrors = validateKnowledgeArticleServerSide(
          normalizedPayload,
          cleanId
        );
        if (validationErrors.length > 0) {
          throw createHttpError(
            400,
            "Bài viết tri thức chưa đạt chuẩn schema để xuất bản.",
            { validationErrors }
          );
        }

        const prevPubData = pubSnap.exists ? pubSnap.data() || {} : {};
        const nextVersion = Number(prevPubData.publishedVersion || 0) + 1;

        const publishedDoc = {
          ...normalizedPayload,
          publishedVersion: nextVersion,
          publishedAt: nowIso,
          publishedBy: caller.uid,
          publishedByEmail: caller.email,
          updatedAt: nowIso,
          updatedBy: caller.uid,
          changeNote: String(changeNote || "").trim().substring(0, 200),
          // Bảo toàn lịch sử: không xóa tài liệu khi tạm ngưng
          createdAt: prevPubData.createdAt || nowIso,
        };

        tx.set(pubRef, publishedDoc);

        if (draftSnap.exists) {
          tx.set(
            draftRef,
            {
              isActive: effectiveActive,
              lastPublishedVersion: nextVersion,
              lastPublishedAt: nowIso,
              lastPublishedBy: caller.uid,
            },
            { merge: true }
          );
        }

        const logRef = db.collection("admin_logs").doc();
        const statusDesc = effectiveActive ? "Đang bật hiển thị" : "Tạm ngưng (giữ nguyên lịch sử)";
        tx.set(logRef, {
          adminId: caller.uid,
          adminEmail: caller.email,
          action: "PUBLISH_KNOWLEDGE",
          targetType: "knowledge",
          targetId: cleanId,
          targetLabel: normalizedPayload.title,
          result: "success",
          details: `Xuất bản bài viết tri thức "${normalizedPayload.title}" v${nextVersion} [${statusDesc}]. ${String(changeNote || "").trim()}`.trim(),
          source: "cloud_function",
          createdAt: nowIso,
        });

        responseData = {
          success: true,
          articleId: cleanId,
          title: normalizedPayload.title,
          publishedVersion: nextVersion,
          isActive: effectiveActive,
          logId: logRef.id,
          publishedAt: nowIso,
        };
      });

      res.status(200).json(responseData);
    } catch (error) {
      if (logger && typeof logger.error === "function") {
        logger.error("Lỗi adminPublishKnowledgeBase:", error.message || error);
      }
      sendErrorResponse(res, error, "Không thể xuất bản bài viết tri thức tài chính.");
    }
  }

  function _stripJsonFence(text) {
    let cleaned = String(text || "").trim();
    if (cleaned.startsWith("```")) {
      cleaned = cleaned.replace(/^```(?:json)?\s*/i, "");
      cleaned = cleaned.replace(/\s*```$/, "").trim();
    }
    const start = cleaned.indexOf("{");
    const end = cleaned.lastIndexOf("}");
    if (start >= 0 && end > start) {
      return cleaned.substring(start, end + 1);
    }
    return cleaned;
  }

  function _validateStructuredPlanJsonText(rawText) {
    const errors = [];
    let parsed = null;
    try {
      const jsonSlice = _stripJsonFence(rawText);
      parsed = JSON.parse(jsonSlice);
    } catch (e) {
      return {
        jsonValid: false,
        validationErrors: ["Phản hồi không phải JSON hợp lệ."],
        parsedJson: null,
      };
    }

    if (!parsed || typeof parsed !== "object" || Array.isArray(parsed)) {
      return {
        jsonValid: false,
        validationErrors: ["JSON gốc phải là Object chứa 4 trường theo hợp đồng."],
        parsedJson: null,
      };
    }

    if (typeof parsed.executiveSummary !== "string" || !parsed.executiveSummary.trim()) {
      errors.push("Thiếu trường chuỗi không rỗng: executiveSummary.");
    }
    if (!Array.isArray(parsed.behavioralInsights) || parsed.behavioralInsights.length === 0) {
      errors.push("Thiếu hoặc rỗng mảng chuỗi: behavioralInsights.");
    }
    if (
      !parsed.categoryActionTips ||
      typeof parsed.categoryActionTips !== "object" ||
      Array.isArray(parsed.categoryActionTips)
    ) {
      errors.push("Thiếu đối tượng map: categoryActionTips.");
    }
    if (typeof parsed.savingStrategyNote !== "string" || !parsed.savingStrategyNote.trim()) {
      errors.push("Thiếu trường chuỗi không rỗng: savingStrategyNote.");
    }

    return {
      jsonValid: errors.length === 0,
      validationErrors: errors,
      parsedJson: errors.length === 0 ? parsed : null,
    };
  }

  async function adminRunSandbox(req, res) {
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method Not Allowed" });
      return;
    }

    const startedMs = nowProvider();
    try {
      const caller = await verifyCaller(req);
      const body = req.body || {};

      if (containsForbiddenSecretField(body)) {
        throw createHttpError(
          400,
          "Request AI Sandbox không được chứa API Key hoặc khóa bí mật từ Client."
        );
      }
      if (body.realUserId || body.userId || body.targetUserId) {
        throw createHttpError(
          400,
          "AI Sandbox chỉ được chạy trên Synthetic Persona, tuyệt đối không nhận userId người dùng thật."
        );
      }

      // Xác thực tham số model & temperature theo Whitelist hệ thống
      const validationErrors = [];
      const primaryModel = String(body.primaryModel || "gemini-3.5-flash").trim();
      const rawFallbacks = Array.isArray(body.fallbackModels) ? body.fallbackModels : [];
      const temperature =
        body.temperature === undefined || body.temperature === null
          ? 0.35
          : Number(body.temperature);
      const prompt = String(body.prompt || "").trim();
      const systemInstruction = String(body.systemInstruction || "").trim();
      const mode = String(body.mode || "chat_prompt").trim();
      const expectStructuredPlanJson = body.expectStructuredPlanJson === true;

      if (!SUPPORTED_GEMINI_MODELS.includes(primaryModel)) {
        validationErrors.push(`Model chính "${primaryModel}" không thuộc danh sách Whitelist.`);
      } else if (MUTABLE_ALIAS_GEMINI_MODELS.includes(primaryModel)) {
        validationErrors.push(`Không được chọn alias động "${primaryModel}" làm model chính.`);
      }

      const cleanFallbacks = [];
      for (const fb of rawFallbacks) {
        const fbStr = String(fb || "").trim();
        if (!fbStr) continue;
        if (!SUPPORTED_GEMINI_MODELS.includes(fbStr)) {
          validationErrors.push(`Model dự phòng "${fbStr}" không thuộc danh sách Whitelist.`);
        } else if (!cleanFallbacks.includes(fbStr) && fbStr !== primaryModel) {
          cleanFallbacks.push(fbStr);
        }
      }
      if (
        cleanFallbacks.length > 0 &&
        cleanFallbacks.every((m) => MUTABLE_ALIAS_GEMINI_MODELS.includes(m))
      ) {
        validationErrors.push(
          "Không được chỉ cấu hình alias động (gemini-flash-latest) làm model dự phòng duy nhất."
        );
      }

      if (Number.isNaN(temperature) || !Number.isFinite(temperature) || temperature < 0.1 || temperature > 0.8) {
        validationErrors.push("Temperature phải nằm trong khoảng 0.1 đến 0.8.");
      }

      if (!prompt || prompt.length > 8000) {
        validationErrors.push("Nội dung prompt thử nghiệm phải từ 1 đến 8000 ký tự.");
      }
      if (systemInstruction.length > 8000) {
        validationErrors.push("systemInstruction không được vượt quá 8000 ký tự.");
      }

      if (validationErrors.length > 0) {
        throw createHttpError(400, "Tham số AI Sandbox không hợp lệ.", { validationErrors });
      }

      // Kiểm tra giới hạn tần suất (Rate limit theo từng Admin UID trước khi gọi Gemini API)
      const nowMs = nowProvider();
      const recentCalls = (sandboxRateLimiter.get(caller.uid) || []).filter(
        (ts) => nowMs - ts < sandboxRateLimitWindowMs
      );
      if (recentCalls.length >= sandboxRateLimitMaxCalls) {
        throw createHttpError(
          429,
          "Admin đang chạy thử nghiệm AI Sandbox quá nhanh. Vui lòng đợi ít giây rồi thử lại."
        );
      }
      recentCalls.push(nowMs);
      sandboxRateLimiter.set(caller.uid, recentCalls);

      const apiKey = String((await geminiApiKeyGetter()) || "").trim();
      if (!apiKey) {
        throw createHttpError(
          503,
          "GEMINI_API_KEY chưa được cấu hình trong Secret Manager của Cloud Functions."
        );
      }
      if (typeof fetchImpl !== "function") {
        throw createHttpError(500, "Môi trường Node hiện tại không hỗ trợ fetch để gọi Gemini API.");
      }

      const modelChain = [primaryModel, ...cleanFallbacks];
      const triedModels = [];
      let responseText = "";
      let modelUsed = null;
      let lastModelError = null;

      for (const modelName of modelChain) {
        triedModels.push(modelName);
        const controller = new AbortController();
        const timer = setTimeout(() => controller.abort(), sandboxTimeoutMs);

        try {
          const endpoint = `https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(
            modelName
          )}:generateContent`;

          const requestPayload = {
            contents: [{ role: "user", parts: [{ text: prompt }] }],
            generationConfig: {
              temperature: temperature,
              ...(expectStructuredPlanJson ? { responseMimeType: "application/json" } : {}),
            },
            ...(systemInstruction
              ? {
                  systemInstruction: {
                    parts: [{ text: systemInstruction }],
                  },
                }
              : {}),
          };

          const apiResp = await fetchImpl(endpoint, {
            method: "POST",
            headers: {
              "Content-Type": "application/json",
              "x-goog-api-key": apiKey,
            },
            body: JSON.stringify(requestPayload),
            signal: controller.signal,
          });

          const respJson = await apiResp.json().catch(() => ({}));
          if (!apiResp.ok) {
            const safeMsg =
              (respJson && respJson.error && respJson.error.message) ||
              `HTTP ${apiResp.status}`;
            lastModelError = `${modelName}: ${safeMsg}`;
            continue;
          }

          const parts =
            respJson &&
            respJson.candidates &&
            respJson.candidates[0] &&
            respJson.candidates[0].content &&
            respJson.candidates[0].content.parts;
          const textOut = Array.isArray(parts)
            ? parts.map((p) => (p && typeof p.text === "string" ? p.text : "")).join("").trim()
            : "";

          if (!textOut) {
            lastModelError = `${modelName}: Phản hồi Gemini trả về rỗng.`;
            continue;
          }

          responseText = textOut;
          modelUsed = modelName;
          break;
        } catch (callErr) {
          if (callErr && callErr.name === "AbortError") {
            lastModelError = `${modelName}: Quá thời gian chờ (${sandboxTimeoutMs}ms).`;
          } else {
            lastModelError = `${modelName}: Lỗi kết nối tới Gemini API.`;
          }
        } finally {
          clearTimeout(timer);
        }
      }

      if (!modelUsed) {
        throw createHttpError(
          502,
          `Tất cả model Gemini trong chuỗi fallback đều thất bại (${lastModelError || "Unknown"}).`
        );
      }

      let jsonCheck = {
        jsonValid: null,
        validationErrors: [],
        parsedJson: null,
      };
      if (expectStructuredPlanJson) {
        jsonCheck = _validateStructuredPlanJsonText(responseText);
      }

      const latencyMs = Math.max(0, nowProvider() - startedMs);
      const nowIso = new Date(nowProvider()).toISOString();
      const personaId =
        body.persona && typeof body.persona.id === "string" ? body.persona.id : "synthetic";

      // Chỉ ghi metadata an toàn, KHÔNG ghi API key hoặc nội dung prompt nhạy cảm vào admin_logs
      const logRef = await db.collection("admin_logs").add({
        adminId: caller.uid,
        adminEmail: caller.email,
        action: "RUN_SANDBOX",
        targetType: "sandbox",
        targetId: mode.substring(0, 60),
        targetLabel: `AI Sandbox (${modelUsed})`,
        result: "success",
        details: `Chạy thử Gemini Sandbox mode=${mode}, persona=${personaId}, model=${modelUsed}, temp=${temperature}, latency=${latencyMs}ms.`,
        source: "cloud_function",
        createdAt: nowIso,
      });

      res.status(200).json({
        success: true,
        modelUsed: modelUsed,
        triedModels: triedModels,
        responseText: responseText,
        jsonValid: jsonCheck.jsonValid,
        jsonValidationErrors: jsonCheck.validationErrors,
        latencyMs: latencyMs,
        logId: logRef.id,
        draftVerificationNote:
          "Kết quả thử nghiệm phản hồi Gemini Sandbox chỉ dùng để kiểm tra prompt/model. Để xuất bản cấu hình nháp, vẫn cần chạy adminVerifyDraftInSandbox để ký HMAC Hash.",
      });
    } catch (error) {
      if (logger && typeof logger.error === "function") {
        // Không bao giờ log đối tượng error thô phòng rò rỉ header/key
        logger.error("Lỗi adminRunSandbox:", error && error.message ? error.message : "Unknown");
      }
      sendErrorResponse(res, error, "Không thể chạy thử nghiệm Gemini AI Sandbox.");
    }
  }

  /**
   * 9. Quản trị Danh mục Hệ thống (`system_categories`) + Audit Log phía Server
   */
  async function adminManageSystemCategory(req, res) {
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method Not Allowed" });
      return;
    }
    try {
      const caller = await verifyCaller(req);
      const { action, template, isNew, categoryId, isActive, categoryName, seedItems } =
        req.body || {};

      const nowIso = new Date(nowProvider()).toISOString();
      const col = db.collection("system_categories");

      if (action === "save") {
        if (!template || typeof template !== "object") {
          throw createHttpError(400, "Thiếu thông tin template danh mục hệ thống.");
        }
        const name = String(template.name || "").trim();
        const type = template.type === "income" ? "income" : "expense";
        const icon = String(template.icon || "category").trim();
        const color = Number(template.color);
        if (!name || name.length > 80 || Number.isNaN(color)) {
          throw createHttpError(400, "Tên hoặc màu sắc danh mục hệ thống không hợp lệ.");
        }

        const docRef =
          template.id && String(template.id).trim()
            ? col.doc(String(template.id).trim())
            : col.doc();

        const dataToSave = {
          id: docRef.id,
          name: name,
          type: type,
          icon: icon,
          color: Math.trunc(color),
          isEssential: template.isEssential === true,
          isActive: template.isActive !== false,
          createdAt: template.createdAt || nowIso,
          updatedAt: nowIso,
        };
        await docRef.set(dataToSave, { merge: true });

        const actionCode = isNew ? "CREATE_SYSTEM_CATEGORY" : "UPDATE_SYSTEM_CATEGORY";
        const logRef = await db.collection("admin_logs").add({
          adminId: caller.uid,
          adminEmail: caller.email,
          action: actionCode,
          targetType: "system_category",
          targetId: docRef.id,
          targetLabel: name,
          result: "success",
          details: `${isNew ? "Tạo mới" : "Cập nhật"} danh mục hệ thống "${name}" (${type}, ${
            dataToSave.isEssential ? "Thiết yếu" : "Linh hoạt"
          }).`,
          source: "cloud_function",
          createdAt: nowIso,
        });

        res.status(200).json({
          success: true,
          categoryId: docRef.id,
          logId: logRef.id,
        });
        return;
      }

      if (action === "toggle_active") {
        const id = String(categoryId || "").trim();
        if (!id || typeof isActive !== "boolean") {
          throw createHttpError(400, "Tham số categoryId hoặc isActive không hợp lệ.");
        }
        await col.doc(id).set(
          {
            isActive: isActive,
            updatedAt: nowIso,
          },
          { merge: true }
        );
        const label = String(categoryName || id).trim();
        const logRef = await db.collection("admin_logs").add({
          adminId: caller.uid,
          adminEmail: caller.email,
          action: isActive ? "SHOW_SYSTEM_CATEGORY" : "HIDE_SYSTEM_CATEGORY",
          targetType: "system_category",
          targetId: id,
          targetLabel: label,
          result: "success",
          details: isActive
            ? `Hiển thị lại danh mục mẫu "${label}".`
            : `Ẩn danh mục mẫu "${label}" khỏi gợi ý tạo mới.`,
          source: "cloud_function",
          createdAt: nowIso,
        });

        res.status(200).json({
          success: true,
          categoryId: id,
          isActive: isActive,
          logId: logRef.id,
        });
        return;
      }

      if (action === "seed_defaults") {
        if (!Array.isArray(seedItems) || seedItems.length === 0 || seedItems.length > 50) {
          throw createHttpError(400, "Danh sách seedItems không hợp lệ.");
        }
        for (const item of seedItems) {
          const itemId = String(item.id || "").trim();
          const itemName = String(item.name || "").trim();
          if (!itemId || !itemName) continue;
          await col.doc(itemId).set(
            {
              id: itemId,
              name: itemName,
              type: item.type === "income" ? "income" : "expense",
              icon: String(item.icon || "category"),
              color: Number.isFinite(Number(item.color)) ? Math.trunc(Number(item.color)) : 0xFF607D8B,
              isEssential: item.isEssential === true,
              isActive: true,
              createdAt: nowIso,
              updatedAt: nowIso,
            },
            { merge: true }
          );
        }
        const logRef = await db.collection("admin_logs").add({
          adminId: caller.uid,
          adminEmail: caller.email,
          action: "SEED_SYSTEM_CATEGORIES",
          targetType: "system_category",
          targetId: "system_categories",
          targetLabel: `Bộ danh mục chuẩn (${seedItems.length} danh mục)`,
          result: "success",
          details: `Khởi tạo ${seedItems.length} danh mục mẫu mặc định cho hệ thống.`,
          source: "cloud_function",
          createdAt: nowIso,
        });

        res.status(200).json({
          success: true,
          seededCount: seedItems.length,
          logId: logRef.id,
        });
        return;
      }

      throw createHttpError(400, 'Tham số action không hợp lệ (chỉ nhận save, toggle_active, seed_defaults).');
    } catch (error) {
      if (logger && typeof logger.error === "function") {
        logger.error("Lỗi adminManageSystemCategory:", error.message || error);
      }
      sendErrorResponse(res, error, "Không thể cập nhật danh mục hệ thống.");
    }
  }

  /**
   * 10. Quản trị Thông báo Hệ thống (`system_announcements`) + Audit Log phía Server
   */
  async function adminManageAnnouncement(req, res) {
    if (req.method !== "POST") {
      res.status(405).json({ error: "Method Not Allowed" });
      return;
    }
    try {
      const caller = await verifyCaller(req);
      const { action, announcement, isNew, announcementId, isActive, title } = req.body || {};
      const nowIso = new Date(nowProvider()).toISOString();
      const col = db.collection("system_announcements");

      if (action === "save") {
        if (!announcement || typeof announcement !== "object") {
          throw createHttpError(400, "Thiếu dữ liệu announcement.");
        }
        const annTitle = String(announcement.title || "").trim();
        const annContent = String(
          announcement.content !== undefined
            ? announcement.content
            : announcement.message || ""
        ).trim();
        if (!annTitle || annTitle.length > 150 || !annContent || annContent.length > 1000) {
          throw createHttpError(400, "Tiêu đề hoặc nội dung thông báo hệ thống không hợp lệ.");
        }

        const docRef =
          announcement.id && String(announcement.id).trim()
            ? col.doc(String(announcement.id).trim())
            : col.doc();

        await docRef.set(
          {
            id: docRef.id,
            title: annTitle,
            content: annContent,
            isActive: announcement.isActive !== false,
            createdBy: announcement.createdBy || caller.email || caller.uid,
            createdAt: announcement.createdAt || nowIso,
            updatedAt: nowIso,
          },
          { merge: true }
        );

        const logRef = await db.collection("admin_logs").add({
          adminId: caller.uid,
          adminEmail: caller.email,
          action: isNew ? "CREATE_ANNOUNCEMENT" : "UPDATE_ANNOUNCEMENT",
          targetType: "system_announcement",
          targetId: docRef.id,
          targetLabel: annTitle,
          result: "success",
          details: `${isNew ? "Tạo thông báo hệ thống mới" : "Cập nhật thông báo hệ thống"} "${annTitle}".`,
          source: "cloud_function",
          createdAt: nowIso,
        });

        res.status(200).json({
          success: true,
          announcementId: docRef.id,
          logId: logRef.id,
        });
        return;
      }

      if (action === "toggle_active") {
        const id = String(announcementId || "").trim();
        if (!id || typeof isActive !== "boolean") {
          throw createHttpError(400, "Tham số announcementId hoặc isActive không hợp lệ.");
        }
        await col.doc(id).set(
          {
            isActive: isActive,
            updatedAt: nowIso,
          },
          { merge: true }
        );
        const label = String(title || id).trim();
        const logRef = await db.collection("admin_logs").add({
          adminId: caller.uid,
          adminEmail: caller.email,
          action: isActive ? "ACTIVATE_ANNOUNCEMENT" : "DEACTIVATE_ANNOUNCEMENT",
          targetType: "system_announcement",
          targetId: id,
          targetLabel: label,
          result: "success",
          details: isActive
            ? `Kích hoạt hiển thị thông báo "${label}".`
            : `Ngừng hiển thị thông báo "${label}".`,
          source: "cloud_function",
          createdAt: nowIso,
        });

        res.status(200).json({
          success: true,
          announcementId: id,
          isActive: isActive,
          logId: logRef.id,
        });
        return;
      }

      if (action === "delete") {
        const id = String(announcementId || "").trim();
        if (!id) {
          throw createHttpError(400, "Thiếu announcementId cần xóa.");
        }
        await col.doc(id).delete();
        const label = String(title || id).trim();
        const logRef = await db.collection("admin_logs").add({
          adminId: caller.uid,
          adminEmail: caller.email,
          action: "DELETE_ANNOUNCEMENT",
          targetType: "system_announcement",
          targetId: id,
          targetLabel: label,
          result: "success",
          details: `Đã xóa thông báo hệ thống "${label}".`,
          source: "cloud_function",
          createdAt: nowIso,
        });

        res.status(200).json({
          success: true,
          announcementId: id,
          logId: logRef.id,
        });
        return;
      }

      throw createHttpError(400, 'Tham số action không hợp lệ (chỉ nhận save, toggle_active, delete).');
    } catch (error) {
      if (logger && typeof logger.error === "function") {
        logger.error("Lỗi adminManageAnnouncement:", error.message || error);
      }
      sendErrorResponse(res, error, "Không thể cập nhật thông báo hệ thống.");
    }
  }

  return {
    adminVerifySession,
    adminSetUserRole,
    adminPublishKnowledgeBase,
    adminRunSandbox,
    adminManageSystemCategory,
    adminManageAnnouncement,
  };
}

module.exports = {
  ALLOWED_CONFIG_TYPES,
  SUPPORTED_GEMINI_MODELS,
  MUTABLE_ALIAS_GEMINI_MODELS,
  FORBIDDEN_SECRET_KEYS,
  ALLOWED_KNOWLEDGE_TOPICS,
  ALLOWED_KNOWLEDGE_TRIGGERS,
  CANONICAL_EXPENSE_GROUPS,
  CANONICAL_INCOME_GROUPS,
  CANONICAL_WALLET_TYPES,
  PROTECTED_EXPENSE_KEYWORDS,
  PROTECTED_INCOME_KEYWORDS,
  PROTECTED_PAYMENT_PROVIDER_KEYS,
  FINANCIAL_HEURISTICS_RANGES,
  createHttpError,
  normalizeVietnameseKeyword,
  containsForbiddenSecretField,
  canonicalizeJsonValue,
  computeCanonicalConfigHash,
  validateConfigPayloadServerSide,
  validateKnowledgeArticleServerSide,
  verifyAdminCallerWithDeps,
  createAdminEndpointHandlers,
};
