# Supabase Setup Guide for Daily Manna

## 🚀 Epic 0.2 Implementation - Step by Step

Follow these steps to complete the Supabase setup for Daily Manna:

## Step 1: Create Supabase Project

1. Go to [supabase.com](https://supabase.com) and create an account
2. Click "New Project"
3. Choose your organization
4. Fill in project details:
   - **Name**: `daily-manna`
   - **Database Password**: Generate a strong password (save it!)
   - **Region**: Choose closest to you
5. Click "Create new project"
6. Wait 2-3 minutes for initialization

## Step 2: Update Configuration

1. Once your project is ready, go to **Settings → API**
2. Copy these values:
   - **Project URL**: `https://[your-project-id].supabase.co`
   - **Project API Keys → anon public**: `eyJ...`

3. Update `DailyManna/Supabase-Config.plist`:
```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>SUPABASE_URL</key>
    <string>https://your-actual-project-id.supabase.co</string>
    <key>SUPABASE_ANON_KEY</key>
    <string>your-actual-anon-key-here</string>
</dict>
</plist>
```

## Step 3: Add Supabase Package

1. In Xcode: **File → Add Package Dependencies**
2. Enter URL: `https://github.com/supabase/supabase-swift`
3. Select **Up to Next Major Version**
4. Click **Add Package**
5. Add to target: **DailyManna**

## Step 4: Database Schema Setup

Go to **Supabase Dashboard → SQL Editor** and run this SQL:

```sql
-- Enable necessary extensions
CREATE EXTENSION IF NOT EXISTS "uuid-ossp";

-- Users table (extends Supabase Auth)
-- NOTE: id references auth.users and is populated by an AFTER INSERT trigger.
CREATE TABLE IF NOT EXISTS users (
  id UUID PRIMARY KEY REFERENCES auth.users(id) ON DELETE CASCADE,
  email TEXT,
  full_name TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Time buckets (fixed buckets)
CREATE TABLE IF NOT EXISTS time_buckets (
  key TEXT PRIMARY KEY,
  name TEXT NOT NULL
);

-- Insert fixed time buckets
INSERT INTO time_buckets (key, name) VALUES
('THIS_WEEK', 'This Week'),
('WEEKEND', 'Weekend'),
('NEXT_WEEK', 'Next Week'),
('NEXT_MONTH', 'Next Month'),
('ROUTINES', 'Routines')
ON CONFLICT (key) DO NOTHING;

-- Tasks table
CREATE TABLE IF NOT EXISTS tasks (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  bucket_key TEXT NOT NULL REFERENCES time_buckets(key),
  parent_task_id UUID NULL REFERENCES tasks(id) ON DELETE CASCADE,
  title TEXT NOT NULL,
  description TEXT,
  due_at TIMESTAMPTZ,
  recurrence_rule TEXT,
  is_completed BOOLEAN NOT NULL DEFAULT FALSE,
  completed_at TIMESTAMPTZ,
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ,
  
  CONSTRAINT valid_bucket_key CHECK (bucket_key IN ('THIS_WEEK','WEEKEND','NEXT_WEEK','NEXT_MONTH','ROUTINES'))
);

-- Labels table
CREATE TABLE IF NOT EXISTS labels (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  name TEXT NOT NULL,
  color TEXT NOT NULL DEFAULT '#007AFF',
  created_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  deleted_at TIMESTAMPTZ,
  
  UNIQUE(user_id, name)
);

-- Task-Label junction table
CREATE TABLE IF NOT EXISTS task_labels (
  task_id UUID NOT NULL REFERENCES tasks(id) ON DELETE CASCADE,
  label_id UUID NOT NULL REFERENCES labels(id) ON DELETE CASCADE,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  
  PRIMARY KEY (task_id, label_id)
);
```

## Step 5: Create Indexes

Run this SQL to add performance indexes:

```sql
-- Performance indexes
CREATE INDEX IF NOT EXISTS idx_tasks_user_updated ON tasks (user_id, updated_at);
CREATE INDEX IF NOT EXISTS idx_tasks_user_bucket ON tasks (user_id, bucket_key, is_completed, due_at);
CREATE INDEX IF NOT EXISTS idx_tasks_parent ON tasks (user_id, parent_task_id);
CREATE INDEX IF NOT EXISTS idx_labels_user_name ON labels (user_id, name);
CREATE INDEX IF NOT EXISTS idx_task_labels_task ON task_labels (task_id);
CREATE INDEX IF NOT EXISTS idx_task_labels_label ON task_labels (label_id);
```

## Step 6: Add Update Triggers

Run this SQL to create automatic updated_at triggers:

```sql
-- Function to update updated_at timestamp
CREATE OR REPLACE FUNCTION touch_updated_at()
RETURNS TRIGGER LANGUAGE plpgsql AS $$
BEGIN
  NEW.updated_at = NOW();
  RETURN NEW;
END $$;

-- Triggers for automatic updated_at
CREATE TRIGGER trg_users_updated_at
  BEFORE UPDATE ON users
  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

CREATE TRIGGER trg_tasks_updated_at
  BEFORE UPDATE ON tasks
  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();

CREATE TRIGGER trg_labels_updated_at
  BEFORE UPDATE ON labels
  FOR EACH ROW EXECUTE FUNCTION touch_updated_at();
```

## Step 7: Setup Row-Level Security (RLS)

Run this SQL to enable secure user isolation:

```sql
-- Enable RLS on all user tables
ALTER TABLE users ENABLE ROW LEVEL SECURITY;
ALTER TABLE tasks ENABLE ROW LEVEL SECURITY;
ALTER TABLE labels ENABLE ROW LEVEL SECURITY;
ALTER TABLE task_labels ENABLE ROW LEVEL SECURITY;

-- Users policies
-- Idempotent creation of the users policy
DO $$
BEGIN
  IF NOT EXISTS (
    SELECT 1 FROM pg_policies
    WHERE schemaname = 'public'
      AND tablename  = 'users'
      AND policyname = 'Users can manage their row'
  ) THEN
    CREATE POLICY "Users can manage their row" ON users
      FOR ALL USING (auth.uid() = id)
      WITH CHECK (auth.uid() = id);
  END IF;
END$$;

-- Tasks policies
CREATE POLICY "tasks_own_data" ON tasks
  FOR ALL USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Labels policies  
CREATE POLICY "labels_own_data" ON labels
  FOR ALL USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Task-labels policies
CREATE POLICY "task_labels_own_data" ON task_labels
  FOR ALL USING (auth.uid() = user_id)
  WITH CHECK (auth.uid() = user_id);

-- Time buckets are world-readable (same for everyone)
ALTER TABLE time_buckets ENABLE ROW LEVEL SECURITY;
CREATE POLICY "time_buckets_read_all" ON time_buckets
  FOR SELECT USING (true);
```

## Step 8: Setup User Registration Function (hardened)

Run this SQL to automatically create user profiles:

```sql
-- Robust, idempotent function to create public.users row when a new auth.users row is inserted
DROP FUNCTION IF EXISTS public.handle_new_user() CASCADE;

CREATE OR REPLACE FUNCTION public.handle_new_user()
RETURNS TRIGGER
LANGUAGE plpgsql
SECURITY DEFINER
SET search_path = public
AS $$
BEGIN
  INSERT INTO public.users (id, email, full_name)
  VALUES (
    NEW.id,
    NEW.email,
    COALESCE(NEW.raw_user_meta_data->>'full_name', NEW.email, '')
  )
  ON CONFLICT (id) DO NOTHING; -- idempotent
  RETURN NEW;
END $$;

ALTER FUNCTION public.handle_new_user() OWNER TO postgres;

-- Recreate the trigger on auth.users
DROP TRIGGER IF EXISTS on_auth_user_created ON auth.users;
CREATE TRIGGER on_auth_user_created
  AFTER INSERT ON auth.users
  FOR EACH ROW EXECUTE FUNCTION public.handle_new_user();
```

Tip: You can verify the trigger exists with:
```sql
select trigger_schema, event_object_schema, event_object_table, trigger_name
from information_schema.triggers
where event_object_schema in ('auth','public')
order by event_object_schema, event_object_table, trigger_name;
```

## Step 9: Configure Authentication Providers

### Sign in with Apple Setup

**IMPORTANT CONCEPT**: For Apple Sign-In, you need TWO different identifiers:
1. **Services ID**: `com.rubentena.DailyManna.signin` (for Sign In with Apple configuration)
2. **App ID**: `com.rubentena.DailyManna` (your actual app bundle ID)

The Services ID is what you configure for Sign In with Apple, and it references your main App ID.

#### 9.1: Apple Developer Account Configuration

**FIRST, you need to create your main App ID (if you don't have one already):**

1. **Go to [Apple Developer Portal](https://developer.apple.com/account/)**
2. **Sign in with your Apple Developer account**
3. **Navigate to Certificates, Identifiers & Profiles**
4. **Click on "Identifiers" in the left sidebar**
5. **Click the "+" button to create a new identifier**
6. **Select "App IDs" (not Services IDs) and click "Continue"**
7. **Select "App" and click "Continue"**
8. **Fill in the form:**
   - **Description**: `Daily Manna App`
   - **Bundle ID**: `com.rubentena.DailyManna` (your actual app bundle ID)
   - **Capabilities**: Check "Sign In with Apple"
9. **Click "Continue" and then "Register"**

**NOW create the Services ID for Sign In with Apple:**

10. **Click the "+" button again to create another identifier**
11. **Select "Services IDs" and click "Continue"**
12. **Fill in the form:**
    - **Description**: `Daily Manna Sign In with Apple`
    - **Identifier**: `com.rubentena.DailyManna.signin` (this is DIFFERENT from your main app bundle ID)
13. **Click "Continue" and then "Register"**

#### 9.2: Configure Sign In with Apple

**IMPORTANT**: You are still in the **Apple Developer Portal** website, NOT in Supabase yet.

1. **After creating the Services ID, you'll see a list of your identifiers**
2. **Click on the Services ID you just created** (`com.rubentena.DailyManna`)
3. **You'll see the Services ID details page**
4. **Scroll down to find "Sign In with Apple" section**
5. **Check the box next to "Sign In with Apple"** to enable it
6. **Click "Configure" button** that appears next to the checkbox
7. **A popup will appear asking you to select your primary App ID**
8. **Select your main app identifier** (this should be `com.rubentena.DailyManna` - the App ID you created in step 9.1, NOT the Services ID)
9. **Click "Save"**
10. **You'll be back on the Services ID page**
11. **Click "Edit" button** at the top right
12. **Scroll down to "Sign In with Apple" section again**
13. **Click "Configure" again**
14. **In the configuration popup, you'll see:**
    - **Domains and Subdomains**: Leave this blank (unless you have a custom domain)
    - **Return URLs**: Add `https://alegkdljychslvchmpfb.supabase.co/auth/v1/callback`
15. **Click "Save"**
16. **Click "Continue" and then "Register" to finalize the Services ID**

#### 9.3: Create Authentication Key

1. **In Apple Developer Portal, go to "Keys"**
2. **Click the "+" button to create a new key**
3. **Fill in the form:**
   - **Key Name**: `Daily Manna Auth Key`
   - **Check "Sign In with Apple"**
4. **Click "Configure" and select your Services ID**
5. **Click "Save" and then "Continue"**
6. **Click "Register"**
7. **Download the .p8 file** (you can only download this once!)
8. **Note your:**
   - **Key ID** (10-character string)
   - **Team ID** (10-character string, found in your account)

**To find your Team ID:**
   - **Go back to the main Apple Developer page**
   - **Look at the top-right corner** - you'll see your name/company name
   - **Click on your name/company name**
   - **In the dropdown, you'll see "Membership"**
   - **Click "Membership"**
   - **Your Team ID is displayed** as a 10-character string (e.g., `ABC123DEF4`)
   - **Write this down** - you'll need it for Supabase configuration

#### 9.3.1: Convert .p8 to JWT (Required for Supabase)

**IMPORTANT**: Supabase requires a JWT token, not the raw .p8 file content.

**Option A: Use Supabase's JWT Generator (Recommended)**
1. **Go to [Supabase JWT Generator](https://supabase.com/docs/guides/auth/social-login/auth-apple#generate-jwt)**
2. **Fill in the form:**
   - **Account ID**: Your 10-character Team ID (from step 9.3)
   - **Service ID**: `com.rubentena.DailyManna.signin` (your Services ID from step 9.1)
3. **Click "Generate JWT"**
4. **Copy the generated JWT token** (this is what you'll use in Supabase)

**Option B: Use Node.js Script (Advanced)**
If you prefer to generate it locally, create a file called `generate-jwt.js`:

```javascript
const jwt = require('jsonwebtoken');
const fs = require('fs');

const teamId = 'YOUR_TEAM_ID'; // Replace with your team ID
const keyId = 'YOUR_KEY_ID';   // Replace with your key ID
const privateKey = fs.readFileSync('AuthKey_KEYID.p8'); // Your .p8 file

const token = jwt.sign({}, privateKey, {
  algorithm: 'ES256',
  expiresIn: '180d',
  audience: 'https://appleid.apple.com',
  issuer: teamId,
  keyid: keyId
});

console.log('JWT Token:', token);
```

Then run: `node generate-jwt.js`

#### 9.4: Configure in Supabase

1. **Go to your Supabase project dashboard**
2. **Navigate to Authentication → Providers**
3. **Find "Apple" and click "Enable"**
4. **Fill in the configuration:**
   - **Client IDs** (add both):
     - `com.rubentena.DailyManna.signin` (Services ID)
     - `com.rubentena.DailyManna` (App Bundle ID)
   - **Secret Key (for OAuth)**: Use the JWT token you generated in step 9.3.1 (NOT the raw .p8 file content)
   - **Callback URL**: This should already be pre-filled with `https://alegkdljychslvchmpfb.supabase.co/auth/v1/callback`
5. **Click "Save"**

**Important Notes:**
- **Client IDs**: Add BOTH identifiers to support native (bundle ID audience) and web (services ID audience) flows.
- **Secret Key**: Must be a JWT generated from your .p8 (see 9.3.1). Do NOT paste the raw .p8.
- **Callback URL**: Supabase provides this; add it to the Services ID config in Apple Developer Portal.
- **No Team ID/Key ID fields** in Supabase; used only to generate the JWT.

### Google OAuth Setup

#### 9.5: Google Cloud Console Configuration

1. **Go to [Google Cloud Console](https://console.cloud.google.com/)**
2. **Sign in with your Google account**
3. **Create a new project or select existing one:**
   - Click the project dropdown at the top
   - Click "New Project" or select existing
   - **Project Name**: `Daily-Manna`
4. **Click "Create" and wait for completion**

#### 9.6: Enable Google+ API

1. **In your project, go to "APIs & Services → Library"**
2. **Search for "Google+ API"**
3. **Click on it and click "Enable"**
4. **Also enable "Google Identity and Access Management (IAM) API"**

#### 9.7: Create OAuth 2.0 Credentials

1. **Go to "APIs & Services → Credentials"**
2. **Click "Create Credentials" → "OAuth 2.0 Client IDs"**
3. **If prompted, configure the OAuth consent screen:**
   - **User Type**: External
   - **App Name**: `Daily Manna`
   - **User support email**: Your email
   - **Developer contact information**: Your email
   - **Save and Continue** through all sections
4. **Back to creating credentials, select "iOS" as application type**
5. **Fill in the form:**
   - **Bundle ID**: `com.yourcompany.dailymanna` (your actual bundle ID)
   - **App Store ID**: Leave blank for now
6. **Click "Create"**
7. **Note your Client ID and Client Secret**

#### 9.8: Add Web Application Credentials

1. **Click "Create Credentials" → "OAuth 2.0 Client IDs" again**
2. **Select "Web application"**
3. **Fill in the form:**
   - **Name**: `Daily Manna Web OAuth`
   - **Authorized redirect URIs**: 
     - `https://alegkdljychslvchmpfb.supabase.co/auth/v1/callback`
     - `https://alegkdljychslvchmpfb.supabase.co/auth/v1/callback/google`
4. **Click "Create"**
5. **Note this Client ID and Client Secret as well**

#### 9.9: Configure in Supabase

1. **Go back to your Supabase project dashboard**
2. **Navigate to Authentication → Providers**
3. **Find "Google" and click "Enable"**
4. **Fill in the configuration:**
   - **Client ID**: Use the **Web application** Client ID (from step 9.8)
   - **Client Secret**: Use the **Web application** Client Secret (from step 9.8)
5. **Click "Save"**

#### 9.9.1: Configure iOS Redirect URL (Required for native OAuth)

To return from the browser back into the app during Google OAuth, we use a custom URL scheme. Configure both the app and Supabase:

1. In Xcode: Targets → DailyManna → Info → URL Types
   - **URL Schemes**: `com.rubentena.DailyManna`
   - **Role**: Editor
2. In Supabase Dashboard: Authentication → URL Configuration
   - Under **Additional redirect URLs**, add: `com.rubentena.DailyManna://auth-callback`
3. In code, set a global redirect URL when creating the Supabase client:
   
   ```swift
   // DailyManna/Core/Auth/SupabaseConfig.swift
   final class SupabaseConfig {
       static let shared = SupabaseConfig()

       // Custom scheme callback. Matches URL Type and Supabase Additional redirect URL
       lazy var redirectToURL: URL = {
           let bundleId = Bundle.main.bundleIdentifier ?? "com.rubentena.DailyManna"
           return URL(string: "\(bundleId)://auth-callback")!
       }()

       lazy var client: SupabaseClient = {
           // ... load SUPABASE_URL and SUPABASE_ANON_KEY ...
           return SupabaseClient(
               supabaseURL: URL(string: url)!,
               supabaseKey: anonKey,
               options: .init(auth: .init(redirectToURL: redirectToURL))
           )
       }()
   }
   ```

4. When starting Google sign-in, also pass the same redirect URL explicitly:

   ```swift
   // DailyManna/Core/Auth/AuthenticationService.swift
   func signInWithGoogle() async throws {
       authState = .authenticating
       let redirectURL = SupabaseConfig.shared.redirectToURL
       _ = try await client.auth.signInWithOAuth(
           provider: .google,
           redirectTo: redirectURL
       )
   }
   ```

### 9.10: Test Authentication

1. **Build and run your app** (`Cmd+R` in Xcode)
2. **You should see the sign-in screen**
3. **Test Apple Sign-In:**
   - Tap "Sign in with Apple"
   - Complete the Apple authentication flow
   - You should be redirected back to the app
4. **Test Google OAuth:**
   - Tap "Continue with Google"
   - Complete the Google authentication flow
   - You should be redirected back to the app

### Troubleshooting Common Issues

#### Apple Sign-In Issues:
- **"Invalid client"**: Check your Service ID matches exactly
- **"Invalid key"**: Ensure .p8 file content is copied completely
- **"Invalid team ID"**: Verify your 10-character team ID

#### Google OAuth Issues:
- **"Invalid client"**: Use the Web application Client ID, not iOS
- **"Redirect URI mismatch"**: Check the callback URLs in Google Console
- **"API not enabled"**: Ensure Google+ API is enabled
- **Fatal error: provide a valid redirect URL (AuthClient.Configuration.redirectToURL)**:
  - Add URL Type with scheme `com.rubentena.DailyManna` in Xcode
  - Add `com.rubentena.DailyManna://auth-callback` under Supabase → Auth → URL Configuration → Additional redirect URLs
  - Ensure the app sets `redirectToURL` and passes it to `signInWithOAuth(.google, redirectTo:)`

#### General Issues:
- **Build errors**: Make sure Supabase Swift package is added to your target
- **Network errors**: Verify your Supabase URL and anon key are correct
- **Authentication state not updating**: Check that RLS policies are properly configured

## Step 10: Build and Test

1. Build the project in Xcode (`Cmd+B`)
2. Run the app (`Cmd+R`)
3. You should see the sign-in screen
4. Authentication won't work until you configure the providers

## 🎉 Epic 0.2 Status

After completing these steps, you'll have:

✅ **Supabase Project**: Fully configured backend
✅ **Database Schema**: Production-ready with RLS
✅ **App Integration**: Supabase SDK integrated
✅ **Authentication UI**: Sign-in screens ready
✅ **Session Management**: Secure Keychain storage
✅ **Repository Pattern**: Clean architecture maintained

## Next Steps

To complete the authentication setup:
1. Configure Apple Developer Account for Sign in with Apple
2. Setup Google Cloud Console for Google OAuth
3. Test authentication flows
4. Implement sync functionality

The foundation is now ready for full authentication implementation! 🚀
