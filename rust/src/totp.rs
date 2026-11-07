use hmac::{Hmac, Mac};
use sha1::Sha1;
use sha2::{Sha256, Sha512};
use zeroize::{Zeroize, Zeroizing};

type HmacSha1 = Hmac<Sha1>;
type HmacSha256 = Hmac<Sha256>;
type HmacSha512 = Hmac<Sha512>;

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TotpAlgorithm {
    Sha1,
    Sha256,
    Sha512,
}

#[derive(Clone, Debug, serde::Serialize, serde::Deserialize)]
pub struct TotpCodeResult {
    pub code: String,
    pub seconds_remaining: u32,
    pub period_seconds: u32,
}

pub fn decode_base32(input: &str) -> Result<Zeroizing<Vec<u8>>, String> {
    let clean: String = input
        .chars()
        .filter(|c| !c.is_whitespace() && *c != '-')
        .collect();

    let mut out = Vec::new();
    let mut buffer: u32 = 0;
    let mut bits_left = 0;

    for ch in clean.chars() {
        if ch == '=' {
            break;
        }

        let val = match ch {
            'A'..='Z' => (ch as u8 - b'A') as u32,
            'a'..='z' => (ch as u8 - b'a') as u32,
            '2'..='7' => (ch as u8 - b'2' + 26) as u32,
            _ => return Err(format!("Недопустимый символ Base32: '{ch}'")),
        };

        buffer = (buffer << 5) | val;
        bits_left += 5;

        if bits_left >= 8 {
            bits_left -= 8;
            out.push((buffer >> bits_left) as u8);
            buffer &= (1 << bits_left) - 1;
        }
    }

    if out.is_empty() {
        return Err("Пустой ключ Base32".to_string());
    }

    Ok(Zeroizing::new(out))
}

pub fn generate_totp(
    secret_base32: &str,
    timestamp_secs: u64,
    algorithm: TotpAlgorithm,
    digits: u32,
    period: u32,
) -> Result<TotpCodeResult, String> {
    if digits < 6 || digits > 8 {
        return Err("Поддерживается только 6, 7 или 8 знаков TOTP".to_string());
    }
    if period == 0 {
        return Err("Период обновления TOTP должен быть больше нуля".to_string());
    }

    let mut key = decode_base32(secret_base32)?;
    let counter = timestamp_secs / (period as u64);
    let seconds_remaining = period - ((timestamp_secs % (period as u64)) as u32);
    let counter_bytes = counter.to_be_bytes();

    let hmac_result: Vec<u8> = match algorithm {
        TotpAlgorithm::Sha1 => {
            let mut mac = HmacSha1::new_from_slice(&key)
                .map_err(|e| format!("Ошибка создания HMAC-SHA1: {e}"))?;
            mac.update(&counter_bytes);
            mac.finalize().into_bytes().to_vec()
        }
        TotpAlgorithm::Sha256 => {
            let mut mac = HmacSha256::new_from_slice(&key)
                .map_err(|e| format!("Ошибка создания HMAC-SHA256: {e}"))?;
            mac.update(&counter_bytes);
            mac.finalize().into_bytes().to_vec()
        }
        TotpAlgorithm::Sha512 => {
            let mut mac = HmacSha512::new_from_slice(&key)
                .map_err(|e| format!("Ошибка создания HMAC-SHA512: {e}"))?;
            mac.update(&counter_bytes);
            mac.finalize().into_bytes().to_vec()
        }
    };

    key.zeroize();

    if hmac_result.len() < 20 {
        return Err("Недостаточная длина хэша HMAC".to_string());
    }

    let offset = (hmac_result.last().unwrap() & 0x0f) as usize;
    if offset + 4 > hmac_result.len() {
        return Err("Смещение TOTP выходит за границы хэша".to_string());
    }

    let binary = ((hmac_result[offset] & 0x7f) as u32) << 24
        | ((hmac_result[offset + 1] as u32) << 16)
        | ((hmac_result[offset + 2] as u32) << 8)
        | (hmac_result[offset + 3] as u32);

    let modulus = 10u32.pow(digits);
    let code_num = binary % modulus;
    let code_str = format!("{:0width$}", code_num, width = digits as usize);

    Ok(TotpCodeResult {
        code: code_str,
        seconds_remaining,
        period_seconds: period,
    })
}

pub fn validate_totp(
    secret_base32: &str,
    candidate_code: &str,
    timestamp_secs: u64,
    window_steps: u32,
    period: u32,
) -> Result<bool, String> {
    let clean_code = candidate_code.trim();
    let digits = clean_code.len() as u32;
    if digits != 6 && digits != 8 {
        return Ok(false);
    }

    let current_counter = (timestamp_secs / period as u64) as i64;
    let window = window_steps as i64;

    for step in -window..=window {
        let step_time = ((current_counter + step) * period as i64) as u64;
        if let Ok(res) = generate_totp(secret_base32, step_time, TotpAlgorithm::Sha1, digits, period) {
            if res.code == clean_code {
                return Ok(true);
            }
        }
    }

    Ok(false)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_rfc6238_vector() {
        // Standard RFC 6238 secret: "12345678901234567890" in ASCII
        // Base32 for this is GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ
        let secret = "GEZDGNBVGY3TQOJQGEZDGNBVGY3TQOJQ";
        // At T = 59s -> counter = 1 -> code 287082
        let res = generate_totp(secret, 59, TotpAlgorithm::Sha1, 6, 30).expect("generate totp");
        assert_eq!(res.code, "287082");
        assert_eq!(res.seconds_remaining, 1);

        // At T = 1111111109s -> code 081804
        let res2 = generate_totp(secret, 1111111109, TotpAlgorithm::Sha1, 6, 30).expect("generate totp");
        assert_eq!(res2.code, "081804");
    }

    #[test]
    fn test_validate_totp() {
        let secret = "JBSWY3DPEHPK3PXP"; // "Hello!\xde\xad\xbe\xef"
        let t = 1700000000;
        let res = generate_totp(secret, t, TotpAlgorithm::Sha1, 6, 30).unwrap();
        assert!(validate_totp(secret, &res.code, t, 1, 30).unwrap());
        assert!(!validate_totp(secret, "000000", t, 1, 30).unwrap());
    }
}
