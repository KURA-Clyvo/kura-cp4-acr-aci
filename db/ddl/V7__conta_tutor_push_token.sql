-- ─── V7: Push notification token em CONTA_TUTOR ──────────────────────────────
-- Adiciona suporte a push notifications via Expo/Firebase.
-- Colunas nullable para não quebrar inserts existentes (register-invite).
-- mobile-tutor-rn envia: PATCH /api/v1/tutor/me/push-token
--   payload: { dsPushToken: string, dsPlatforma: 'ios' | 'android' }

ALTER TABLE CONTA_TUTOR
    ADD DS_PUSH_TOKEN VARCHAR2(512);

ALTER TABLE CONTA_TUTOR
    ADD DS_PLATAFORMA_PUSH VARCHAR2(10);

ALTER TABLE CONTA_TUTOR
    ADD CONSTRAINT CHK_PLATAFORMA_PUSH CHECK (DS_PLATAFORMA_PUSH IN ('ios', 'android') OR DS_PLATAFORMA_PUSH IS NULL);

COMMENT ON COLUMN CONTA_TUTOR.DS_PUSH_TOKEN IS 'Token Expo/FCM para push notifications. Nunca logar (LGPD).';
COMMENT ON COLUMN CONTA_TUTOR.DS_PLATAFORMA_PUSH IS 'Plataforma do dispositivo: ios | android. Nullable.';
