#include <jni.h>
#include <algorithm>
#include <cstdint>
#include <vector>
#include "media_codecs/etc.h"
#include "media_codecs/FastNoiseLite.h"

namespace {
void invalid(JNIEnv* env) {
    env->ThrowNew(env->FindClass("java/lang/IllegalArgumentException"),
                  "Invalid imported media texture");
}
bool dimensions(int w, int h) {
    return w > 0 && h > 0 && w <= 4096 && h <= 4096;
}
}

extern "C" JNIEXPORT jbyteArray JNICALL
Java_com_retro_rshop_SocketImportNative_decodeTexture(
    JNIEnv* env, jobject, jbyteArray bytes, jint width, jint height, jint format) {
    if (!dimensions(width, height) || (format != 28 && format != 30 && format != 31)) {
        invalid(env); return nullptr;
    }
    const int blockBytes = format == 30 ? 8 : 16;
    const int length = ((width + 3) / 4) * ((height + 3) / 4) * blockBytes;
    if (env->GetArrayLength(bytes) != length) { invalid(env); return nullptr; }
    try {
        std::vector<uint8_t> input(length);
        env->GetByteArrayRegion(bytes, 0, length, reinterpret_cast<jbyte*>(input.data()));
        std::vector<uint32_t> pixels(static_cast<size_t>(width) * height);
        const int ok = format == 28
            ? decode_eacrg(input.data(), width, height, pixels.data())
            : format == 30 ? decode_etc2(input.data(), width, height, pixels.data())
                           : decode_etc2a8(input.data(), width, height, pixels.data());
        if (!ok) { invalid(env); return nullptr; }
        // Decoder returns BGRA on Android's little-endian architectures.
        for (auto& p : pixels) p = (p & 0xff00ff00u) | ((p & 0xffu) << 16) | ((p >> 16) & 0xffu);
        auto output = env->NewByteArray(static_cast<jsize>(pixels.size() * 4));
        if (output) env->SetByteArrayRegion(output, 0, static_cast<jsize>(pixels.size() * 4),
                                          reinterpret_cast<const jbyte*>(pixels.data()));
        return output;
    } catch (...) { invalid(env); return nullptr; }
}

extern "C" JNIEXPORT jfloatArray JNICALL
Java_com_retro_rshop_SocketImportNative_noise(
    JNIEnv* env, jobject, jint width, jint height, jfloatArray settings) {
    if (!dimensions(width, height) || env->GetArrayLength(settings) != 14) {
        invalid(env); return nullptr;
    }
    try {
        float p[14]; env->GetFloatArrayRegion(settings, 0, 14, p);
        using F = fastnoiselite::FastNoiseLite;
        F noise(static_cast<int>(p[0]));
        noise.SetNoiseType(static_cast<F::NoiseType>(static_cast<int>(p[1])));
        noise.SetFrequency(p[2]);
        noise.SetFractalType(static_cast<F::FractalType>(static_cast<int>(p[3])));
        noise.SetFractalOctaves(static_cast<int>(p[4]));
        noise.SetFractalLacunarity(p[5]); noise.SetFractalGain(p[6]);
        noise.SetFractalWeightedStrength(p[7]); noise.SetFractalPingPongStrength(p[8]);
        noise.SetCellularDistanceFunction(static_cast<F::CellularDistanceFunction>(static_cast<int>(p[9])));
        noise.SetCellularReturnType(static_cast<F::CellularReturnType>(static_cast<int>(p[10])));
        noise.SetCellularJitter(p[11]);
        std::vector<float> values(static_cast<size_t>(width) * height);
        for (int y = 0; y < height; ++y) for (int x = 0; x < width; ++x)
            values[static_cast<size_t>(y) * width + x] = noise.GetNoise(x + p[12], y + p[13]);
        auto output = env->NewFloatArray(static_cast<jsize>(values.size()));
        if (output) env->SetFloatArrayRegion(output, 0, static_cast<jsize>(values.size()), values.data());
        return output;
    } catch (...) { invalid(env); return nullptr; }
}
