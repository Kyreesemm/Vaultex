#[derive(Clone, Debug, serde::Serialize, serde::Deserialize)]
pub struct PasswordStrengthResult {
    /// Оценка от 0 (очень слабый) до 4 (очень стойкий)
    pub score: u8,
    /// Расчетная энтропия пароля в битах
    pub entropy_bits: f64,
    /// Рекомендация или статус на русском языке
    pub feedback: String,
    /// Примерное расчетное время подбора на GPU-кластере
    pub crack_time_display: String,
}

pub fn analyze_password_strength(password: &str) -> PasswordStrengthResult {
    let len = password.chars().count();
    if len == 0 {
        return PasswordStrengthResult {
            score: 0,
            entropy_bits: 0.0,
            feedback: "Пароль пуст".to_string(),
            crack_time_display: "мгновенно".to_string(),
        };
    }

    let mut has_lower = false;
    let mut has_upper = false;
    let mut has_digit = false;
    let mut has_symbol = false;
    let mut has_other = false;

    for ch in password.chars() {
        if ch.is_ascii_lowercase() {
            has_lower = true;
        } else if ch.is_ascii_uppercase() {
            has_upper = true;
        } else if ch.is_ascii_digit() {
            has_digit = true;
        } else if ch.is_ascii_punctuation() || ch.is_whitespace() {
            has_symbol = true;
        } else {
            has_other = true;
        }
    }

    let mut pool_size: f64 = 0.0;
    if has_lower {
        pool_size += 26.0;
    }
    if has_upper {
        pool_size += 26.0;
    }
    if has_digit {
        pool_size += 10.0;
    }
    if has_symbol {
        pool_size += 33.0;
    }
    if has_other {
        pool_size += 50.0;
    }

    if pool_size == 0.0 {
        pool_size = 10.0;
    }

    let mut entropy = (len as f64) * pool_size.log2();

    // Штрафы за однотипность и повторения
    let lower_pwd = password.to_lowercase();
    let common_sequences = [
        "12345", "123456", "password", "qwerty", "admin", "abcdef", "111111", "000000",
    ];
    for seq in &common_sequences {
        if lower_pwd.contains(seq) {
            entropy = (entropy - 20.0).max(5.0);
        }
    }

    // Штраф за малое разнообразие символов при большой длине (например, "aaaaaa")
    let mut unique_chars = std::collections::HashSet::new();
    for ch in password.chars() {
        unique_chars.insert(ch);
    }
    if unique_chars.len() <= 2 && len > 4 {
        entropy = (entropy * 0.4).max(5.0);
    }

    let score = if entropy < 28.0 || len < 6 {
        0
    } else if entropy < 46.0 || len < 8 {
        1
    } else if entropy < 62.0 || len < 11 {
        2
    } else if entropy < 80.0 || len < 14 {
        3
    } else {
        4
    };

    let feedback = match score {
        0 => "Очень ненадежный: мгновенно взламывается по словарю",
        1 => "Слабый пароль: добавьте заглавные буквы, цифры или увеличьте длину",
        2 => "Средний пароль: рекомендуется увеличить длину хотя бы до 14 символов",
        3 => "Надежный пароль: высокая стойкость к перебору",
        _ => "Максимальная защита: криптографически стойкий мастер-пароль",
    }
    .to_string();

    // Оценка времени взлома (при 10^10 попыток в секунду для офлайн GPU кластера)
    let guesses_per_sec = 10_000_000_000.0f64;
    let combinations = 2.0f64.powf(entropy);
    let seconds_to_crack = combinations / (guesses_per_sec * 2.0);

    let crack_time_display = if seconds_to_crack < 1.0 {
        "мгновенно".to_string()
    } else if seconds_to_crack < 60.0 {
        format!("{:.0} сек", seconds_to_crack)
    } else if seconds_to_crack < 3600.0 {
        format!("{:.0} мин", seconds_to_crack / 60.0)
    } else if seconds_to_crack < 86400.0 {
        format!("{:.0} ч", seconds_to_crack / 3600.0)
    } else if seconds_to_crack < 30.0 * 86400.0 {
        format!("{:.0} дн", seconds_to_crack / 86400.0)
    } else if seconds_to_crack < 365.0 * 86400.0 {
        format!("{:.0} мес", seconds_to_crack / (30.0 * 86400.0))
    } else if seconds_to_crack < 1000.0 * 365.0 * 86400.0 {
        format!("{:.0} лет", seconds_to_crack / (365.0 * 86400.0))
    } else {
        "века (>10 000 лет)".to_string()
    };

    PasswordStrengthResult {
        score,
        entropy_bits: (entropy * 10.0).round() / 10.0,
        feedback,
        crack_time_display,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_weak_passwords() {
        let r1 = analyze_password_strength("123456");
        assert_eq!(r1.score, 0);

        let r2 = analyze_password_strength("password");
        assert_eq!(r2.score, 0);
    }

    #[test]
    fn test_strong_passwords() {
        let r = analyze_password_strength("K9#vL@82!mQ$0zR#wX19");
        assert_eq!(r.score, 4);
        assert!(r.entropy_bits > 80.0);
    }
}
