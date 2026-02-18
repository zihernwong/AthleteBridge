# AthleteBridge App Demo Plan

## Overview
AthleteBridge is an iOS platform for the badminton community — connecting players with coaches, stringers, venues, and tournament partners. This demo showcases all major features across both Client and Coach user flows.

---

## Demo 1: Onboarding & Profile Setup

### Client Profile
1. Open the app → Sign up / Sign in
2. Navigate to **Profile** tab
3. Create a client profile:
   - Enter name
   - Upload a profile photo
   - Verify phone number (country code selector + SMS code)
   - Set goals (e.g., Footwork, Smash technique)
   - Select preferred availability (Morning / Afternoon / Evening)
   - Set skill level (Beginner / Intermediate / Advanced)
   - Enter zip code → city auto-fills
   - Add biography
   - Toggle calendar integration (auto-adds confirmed bookings to device calendar)
4. Show additional roles: Stringer, Tournament Organizer, Places to Play Contact

### Coach Profile
1. Switch to a coach account
2. Create a coach profile:
   - Enter name, upload photo, verify phone
   - Set specialties (sourced from dynamic subjects)
   - Set experience years and hourly rate / rate range
   - Set availability and meeting preference (In-Person / Virtual)
   - Enter zip code → city auto-fills
   - Add biography and Tournamentsoftware.com link
3. Show subscription tier badge (Free / Coach Plus / Coach Pro)
4. Tap **Manage Subscription** → show Stripe Checkout integration

---

## Demo 2: Client Home — Coach Discovery

1. From the **Home** tab (client), show the search interface
2. Search for a coach by name → autocomplete suggestions appear
3. Enter improvement areas → suggestions from coaches' specialties
4. Select availability chips → tap **Find Coaches**
5. View matched coach results (MatchResultsView)
6. Tap a coach to view their full profile, specialties, rates, reviews, and bio

---

## Demo 3: Booking Flow

### Client Side
1. From Bookings tab, tap **+** to create a new booking
2. Select a coach, set date/time, add notes
3. Submit booking request
4. Show the booking appears under **Bookings Awaiting Your Confirmation** after coach accepts
5. Confirm the booking → it moves to **Confirmed Bookings**
6. Show the booking auto-added to the device calendar (if toggle enabled)

### Coach Side
1. Switch to coach account → Bookings tab
2. Show incoming booking under **Bookings Awaiting Your Acceptance**
3. Tap **Accept** → set rate, accept the booking
4. Show calendar view with booking markers on dates
5. Navigate months, tap a date to see that day's bookings
6. Show **Input Time Away** feature to mark unavailable dates
7. Show **Locations** management for coaching locations

### Booking Status Flow
- Show color-coded status badges: Requested (blue) → Confirmed (green)
- Show rejection/cancellation flow with reason display
- Show group session indicator and multi-participant status tracking
- Show verified badge next to phone-verified users

---

## Demo 4: Messaging

1. Navigate to **Messages** tab → show conversation list
2. Show unread badge count on the tab
3. Tap **+** to start a new conversation → search coaches/clients
4. Open a chat → show message bubbles (blue sent, gray received)
5. Send a message → show real-time delivery
6. Show read receipts (reader avatar, name, timestamp)
7. Return to list → show last message preview and unread indicator

---

## Demo 5: Payments

### Client Payments
1. Navigate to **Payments** tab
2. Show **Unpaid** tab → list of unpaid bookings
3. Tap **Make Payment** → shows coach's payment handles (Venmo, PayPal, Cash App, Zelle)
4. Tap a platform → deep links to the payment app
5. Tap **Notify Coach of Payment** → sends push notification
6. Switch to **Paid** tab → show completed payments
7. Tap **Payments Summary** → show total paid, breakdown by coach, date range filters

### Coach Payments
1. Switch to coach account → Payments tab
2. Show **Payment Handles** entry (add Venmo, PayPal, etc. with username)
3. Show **Revenue Summary** → total revenue, breakdown by client, date range filters
4. Show billing info on unpaid bookings

---

## Demo 6: Stringing Services

### Register as a Stringer
1. From client Home → Stringing section → **Find a Stringer**
2. Tap **+** to register as a stringer
3. Fill in: name (auto-filled), labor cost, meetup locations
4. Select strings offered from presets (BG65, BG80, etc.) with cost per string
5. Add custom strings if needed → Save

### Place a Stringing Order
1. Browse stringers → tap a stringer to view details
2. Place an order: select racket, string, tension, timeline preference
3. Show order total calculation (labor + string cost)
4. Submit order → stringer receives push notification

### Stringer Order Management
1. Switch to stringer account → Home → **Manage Stringing**
2. Show **Incoming Orders** with pending count badge
3. Tap an order → view order details (racket, string, tension, timeline, total)
4. Walk through the status flow:
   - **Accept** the order
   - Mark as **Stringing** (in progress)
   - Mark as **Ready for Pickup**
5. Show buyer receives push notification at each status change
6. Buyer taps notification → deep links directly to the order detail

### Buyer Order Tracking
1. From client Home → **My Stringing Orders**
2. Show orders with color-coded status badges:
   - Placed (blue), Accepted (orange), Stringing (purple), Ready for Pickup (teal)
3. Tap an order → view details
4. When status is "Ready for Pickup" → tap **Mark as Picked Up**
5. Show **Message Stringer** button to coordinate via in-app chat

---

## Demo 7: Places to Play

### Browse & Add Places
1. From Home → Places to Play → **Browse Places**
2. Show existing places with name, address, price, weekly schedule
3. Tap **+** to add a new venue:
   - Enter name, address, price per session
   - Select days available (chip selector)
   - Set open/close times per day
4. Save → venue appears in the list

### Place Detail View
1. Tap a place → show detail view with:
   - Venue info card (address, price, schedule)
   - **Interactive map** with green pin (auto-geocoded from address)
   - **Driving time** from current location (request location permission if needed)
   - Show: "25 min · 12.3 mi from your current location"
2. Tap **Open in Apple Maps** → opens driving directions
3. Show contact section with message button

### Players to Play With
1. From Home → Places to Play → **Players to Play With**
2. Tap **+** to post yourself → auto-fills from profile (name, skill level, city, availability)
3. Tap the **pencil icon** to edit your player profile:
   - Change skill level, city, availability
   - **Connect venues**: multi-select from existing Places to Play (checkmark picker)
   - Save → connected venue names appear on your listing
4. Show other players with skill level badge, city, availability chips, connected venues
5. Tap **Message** on another player → opens in-app chat

---

## Demo 8: Tournaments

### Find Tournaments
1. From Home → Tournaments → **Find Upcoming Tournaments**
2. Show list of tournaments with dates, location, signup link
3. Tap **+ Suggest** to add a tournament:
   - Enter name, start/end dates, location, signup link
4. Show tournament appears in the list

### Find a Tournament Partner
1. From Home → **Find a Tournament Partner**
2. Search or select a tournament
3. Post yourself as looking for a partner:
   - Select gender (Male / Female)
   - Select events: Men's Doubles, Women's Doubles, Mixed Doubles
   - Select desired skill levels: A, B, C, D
   - Tap **I'm Looking for a Partner**
4. Show compatible partners list (gender + event validation):
   - Men's Doubles: shows other male players
   - Women's Doubles: shows other female players
   - Mixed Doubles: shows opposite gender players
5. Show partner cards with avatar, name, gender, events, skill levels
6. Tap Tournamentsoftware.com link to view their tournament profile
7. Tap **Message** to coordinate partnership

---

## Demo 9: Push Notifications & Deep Links

1. **Chat message notification** → tapping opens the specific conversation
2. **Booking request notification** → tapping navigates to Bookings tab with the specific booking
3. **Payment reminder** → auto-sent 2 hours after session ends, tapping opens Payments tab
4. **Stringing order notification** → tapping navigates directly to the specific order detail
5. **Foreground notifications** → show banner while app is open, auto-refresh data
6. Show notification badge on Messages tab for unread chats

---

## Demo 10: Additional Roles & Features

### Places to Play Contact Role
1. In Profile → enable "Places to Play Contact" additional role
2. Show new **Places Contact** tab appears in the tab bar
3. Manage venue listings from the dedicated contact tab

### Phone Verification
1. Show the verification flow: select country code → enter phone number → receive SMS
2. Show the verified badge (green checkmark) appearing next to name in bookings and profile

### Subscription Tiers (Coach)
1. Show Free tier vs Coach Plus vs Coach Pro
2. Tap Subscribe → Stripe Checkout opens
3. After payment → tier badge updates automatically (synced via Cloud Function)
4. Show Manage Billing → opens Stripe Customer Portal

---

## Demo Summary — Key Differentiators

- **All-in-one badminton platform**: coaching, stringing, venues, tournaments, and player matching
- **Real-time messaging** with read receipts
- **Push notifications** with deep linking to specific content
- **Location-aware**: driving time to venues from current location
- **Apple Maps integration** for venue directions
- **Calendar integration** for confirmed bookings
- **Stripe-powered subscriptions** for coach tiers
- **Multi-role support**: one account can be client, coach, stringer, tournament organizer, and venue contact
