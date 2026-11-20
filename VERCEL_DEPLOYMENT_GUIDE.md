# 🚀 THC Dashboard Vercel Deployment Guide

The **THC Command Center Dashboard** is now 100% prepared and optimized for instant, zero-configuration deployment on **Vercel**.

---

## ⚡ 1-Minute Vercel Deployment (Step-by-Step)

### Option 1: Deploy via Vercel Web Dashboard (Recommended)

1. **Sign in to Vercel**:
   Go to [vercel.com](https://vercel.com) and sign in to your new Vercel account.

2. **Import Repository**:
   - Click **"Add New..."** → **"Project"**.
   - Select your Git provider (GitHub / GitLab / Bitbucket) and import this repository:
     `preeclampsia360-flutter-backend-wired` (or your repo name).

3. **Configure Project Settings**:
   - **Project Name**: `preeclampsia360-thc` (or any custom name)
   - **Framework Preset**: `Other` (Auto-detected)
   - **Root Directory**: `./` (Default root) *or* `thc-dashboard`
   - **Build & Output Settings**: Leave empty / default (No build command required; it is a zero-build static site with edge rewrites).
   - **Environment Variables**: None required! (The live Render backend URL `https://preeclampsia360-api.onrender.com` and proxy rewrites are already configured in `vercel.json`).

4. **Click "Deploy"**:
   - Vercel will deploy the command center in **less than 15 seconds**!
   - You will receive a live URL: `https://<your-project-name>.vercel.app`.

---

### Option 2: Deploy via Vercel CLI

If you have Node.js and the Vercel CLI installed:

```bash
# 1. Install Vercel CLI (if not already installed)
npm i -g vercel

# 2. Login to your Vercel account
vercel login

# 3. Deploy to production
vercel --prod
```

---

## 🎯 Features Configured for Vercel

1. **Edge Proxy Rewrites (`vercel.json`)**:
   - Proxies `/api/*` requests directly to `https://preeclampsia360-api.onrender.com/api/*`.
   - Bypasses browser CORS restrictions completely while maintaining clean relative paths.

2. **Live Backend Sync & Status**:
   - Automatically connects to the live Render cloud backend.
   - Includes a clickable **LIVE SYNC** pill in the top header that opens a **Cloud Server Configuration Modal** to test latency or switch to a custom API URL.

3. **Doctor Authentication**:
   - Auto-authenticates as **Dr. V. Meenakshi (THC MO)** for immediate evaluation and demo testing.
   - Includes a **"⚡ Instant Sign-In"** button and manual Doctor ID / PIN login (`PY-THC-MO-001` / `123456`).

4. **Resilient Cold-Start Fallback**:
   - When Render free tier spins up from sleep (~20s cold start), a polite notification is displayed while the full 27 Puducherry PHCs catalog, sample referrals, and patient charts render immediately with zero blank screens.

5. **Hospital Switcher & Full Network**:
   - Switch between RGGWCH, JIPMER, IGMC&RI, PIMS, and SMVMCH.
   - Real-time emergency red alert pop-up with Web Audio synthesizer chimes.
   - Interactive referral acceptance, triage handover, and patient lab charts (Hb, Urea, Platelet, Creatinine, LFT).

