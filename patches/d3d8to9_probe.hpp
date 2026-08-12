/*
 * Timing probe for d3d8to9 (D3D8TO9_PROBE=<path>, off unless set).
 *
 * DXVK's probes measure everything from the D3D9 boundary downwards. That leaves one layer
 * unaccounted for: this one. A pause measured at DXVK's boundary contains all of d3d8to9's work
 * *and* everything the game and Ashita did, and in-world that pause is ~120 ms per frame.
 *
 * This splits it. It records, per second:
 *   - how long the game spends inside each d3d8to9 entry point   (this layer's own cost)
 *   - how long it spends between them                            (FFXI + Ashita, above us)
 *   - a bucketed histogram of those gaps, so a uniform per-call tax is distinguishable from a
 *     few very large pauses
 *   - which entry point follows each long pause, which says what the game was busy doing
 */
#pragma once

#include <chrono>
#include <cstdint>
#include <cstdio>
#include <cstdlib>

namespace d3d8to9_probe
{
	enum Call
	{
		CallPresent, CallSetRenderState, CallSetTransform, CallSetTexture,
		CallSetTextureStageState, CallDrawPrimitive, CallDrawIndexedPrimitive,
		CallDrawPrimitiveUP, CallDrawIndexedPrimitiveUP, CallSetStreamSource,
		CallSetVertexShader, CallSetVertexShaderConstant, CallSetIndices,
		CallTextureLockRect, CallTextureUnlockRect, CallVBLock, CallIBLock,
		CallCopyRects, CallSetRenderTarget, CallOther, CallCount
	};

	inline const char *name(int c)
	{
		static const char *names[CallCount] = {
			"Present", "SetRenderState", "SetTransform", "SetTexture",
			"SetTextureStageState", "DrawPrimitive", "DrawIndexedPrimitive",
			"DrawPrimitiveUP", "DrawIndexedPrimitiveUP", "SetStreamSource",
			"SetVertexShader", "SetVertexShaderConstant", "SetIndices",
			"TextureLockRect", "TextureUnlockRect", "VBLock", "IBLock",
			"CopyRects", "SetRenderTarget", "Other"
		};
		return names[c];
	}

	struct Probe
	{
		static const size_t NumBuckets = 6;
		// bucket upper bounds, microseconds
		static constexpr double edges[NumBuckets] = { 1, 5, 20, 100, 1000, 1e12 };

		FILE *file = nullptr;
		std::chrono::steady_clock::time_point tick;
		std::chrono::steady_clock::time_point lastExit;
		bool haveExit = false;

		uint64_t calls[CallCount] = {};
		double   inside[CallCount] = {};
		uint64_t gapN[NumBuckets] = {};
		double   gapMs[NumBuckets] = {};
		uint64_t bigBefore[CallCount] = {};
		double   bigBeforeMs[CallCount] = {};

		Probe()
		{
			const char *p = std::getenv("D3D8TO9_PROBE");
			if (p != nullptr && *p != '\0')
				file = std::fopen(p, "a");
			if (file != nullptr)
			{
				std::fprintf(file, "elapsed_s");
				for (int i = 0; i < CallCount; ++i)
					std::fprintf(file, ",%s_n,%s_ms", name(i), name(i));
				for (size_t i = 0; i < NumBuckets; ++i)
					std::fprintf(file, ",gap%zu_n,gap%zu_ms", i, i);
				for (int i = 0; i < CallCount; ++i)
					std::fprintf(file, ",before_%s_n,before_%s_ms", name(i), name(i));
				std::fprintf(file, "\n");
				std::fflush(file);
			}
			tick = std::chrono::steady_clock::now();
		}

		inline bool on() const { return file != nullptr; }

		void enter(int which, std::chrono::steady_clock::time_point t0)
		{
			if (!haveExit)
				return;
			double us = std::chrono::duration<double, std::micro>(t0 - lastExit).count();
			for (size_t i = 0; i < NumBuckets; ++i)
			{
				if (us <= edges[i]) { gapN[i]++; gapMs[i] += us / 1000.0; break; }
			}
			if (us > 100.0)
			{
				bigBefore[which]++;
				bigBeforeMs[which] += us / 1000.0;
			}
		}

		void leave(int which, std::chrono::steady_clock::time_point t0)
		{
			auto now = std::chrono::steady_clock::now();
			calls[which]++;
			inside[which] += std::chrono::duration<double, std::milli>(now - t0).count();
			lastExit = now;
			haveExit = true;

			double dt = std::chrono::duration<double>(now - tick).count();
			if (dt < 1.0)
				return;
			std::fprintf(file, "%.1f", dt);
			for (int i = 0; i < CallCount; ++i)
			{
				std::fprintf(file, ",%.0f,%.1f", calls[i] / dt, inside[i] / dt);
				calls[i] = 0; inside[i] = 0.0;
			}
			for (size_t i = 0; i < NumBuckets; ++i)
			{
				std::fprintf(file, ",%.0f,%.1f", gapN[i] / dt, gapMs[i] / dt);
				gapN[i] = 0; gapMs[i] = 0.0;
			}
			for (int i = 0; i < CallCount; ++i)
			{
				std::fprintf(file, ",%.0f,%.1f", bigBefore[i] / dt, bigBeforeMs[i] / dt);
				bigBefore[i] = 0; bigBeforeMs[i] = 0.0;
			}
			std::fprintf(file, "\n");
			std::fflush(file);
			tick = now;
		}
	};

	inline Probe &probe()
	{
		static Probe instance;
		return instance;
	}

	struct Scope
	{
		std::chrono::steady_clock::time_point t0;
		int which;
		bool active;

		explicit Scope(int w) : which(w), active(probe().on())
		{
			if (active)
			{
				t0 = std::chrono::steady_clock::now();
				probe().enter(which, t0);
			}
		}
		~Scope()
		{
			if (active)
				probe().leave(which, t0);
		}
	};
}

#define D3D8TO9_TIME(call) d3d8to9_probe::Scope probe_scope_(d3d8to9_probe::call)
