# Landmark Dot UI - Passenger App

## Overview
Changed the landmark/stop display on the passenger map from always-visible labeled pins to minimal numbered dots that reveal details on tap.

## Changes Made

### Before
- Landmarks displayed as large pins with labels always visible
- Labels showed: "1. Stop Name", "2. Stop Name", etc.
- Took up significant map space
- Cluttered the map view

### After
- Landmarks displayed as small numbered circular dots
- Only the stop number (1, 2, 3...) is visible
- Tap a dot to see full details in a bottom sheet
- Clean, minimal map interface

## Visual Design

### Dot Appearance
- **Size**: 32x32 pixels
- **Shape**: Circle
- **Background**: Purple (#8A3B5D)
- **Border**: 3px white border
- **Shadow**: Subtle drop shadow for depth
- **Number**: White, bold, centered

### Tap Interaction
When a passenger taps a landmark dot:

1. **Bottom Sheet Opens** with:
   - Stop number badge (matching the dot)
   - Stop name (large, bold)
   - Route context ("Stop #X on Route Name")
   - Coordinates (latitude, longitude)
   - Stop order number

2. **Set as Unload Point Button**:
   - Appears if pickup point is already set
   - Only enabled if stop comes after pickup point
   - One-tap to set as destination
   - Automatically updates map and booking form

3. **Validation Messages**:
   - If no pickup set: "Set your pickup point first"
   - If stop is before pickup: "Choose a stop further along the route"

## User Flow

### Scenario 1: Setting Unload Point via Landmark
1. Passenger sets pickup point on map
2. Passenger taps a landmark dot
3. Bottom sheet shows stop details
4. Passenger taps "Set as unload point"
5. Unload pin automatically placed at that landmark
6. Ready to book

### Scenario 2: Browsing Landmarks
1. Passenger taps any landmark dot
2. Views stop name and details
3. Closes sheet (swipe down or tap outside)
4. Continues exploring map

## Benefits

### For Passengers
✅ **Cleaner Map**: Less visual clutter, easier to see route and jeepneys  
✅ **Quick Reference**: Numbered dots match stop order  
✅ **On-Demand Info**: Details only when needed  
✅ **Easy Unload Selection**: One tap to set destination at known landmarks  
✅ **Better Context**: See stop name, coordinates, and position in route  

### For UX
✅ **Progressive Disclosure**: Show minimal info, reveal more on interaction  
✅ **Touch-Friendly**: 32px dots are easy tap targets  
✅ **Consistent**: Matches modern map app patterns  
✅ **Accessible**: High contrast, clear numbering  

## Technical Implementation

### Component Structure
```dart
// Marker with GestureDetector
Marker(
  point: stop.position,
  width: 32,
  height: 32,
  child: GestureDetector(
    onTap: () => _showLandmarkDetails(stop, stopNumber),
    child: CircularDot(number: stopNumber),
  ),
)
```

### Bottom Sheet Method
```dart
_showLandmarkDetails(RouteStopPoint stop, int stopNumber)
```
- Shows stop information
- Validates if stop can be used as unload point
- Provides "Set as unload point" action
- Updates map state when selected

### Validation Logic
- Checks if pickup point exists
- Uses `_isUnloadAfterPickup()` to verify stop order
- Only enables button if stop comes after pickup on route

## Map Legend

Passengers will see:
- **Purple numbered dots** (1, 2, 3...): Route landmarks/stops
- **Orange pin**: Pickup point (set by passenger)
- **Red pin**: Unload point (set by passenger or landmark)
- **Blue circle**: Passenger's current location
- **Bus icons**: Active jeepneys on route

## Future Enhancements

### Possible Additions
1. **Cluster nearby stops**: Group dots when zoomed out
2. **Highlight nearest stop**: Auto-highlight closest landmark to passenger
3. **Fare preview**: Show estimated fare when tapping landmark
4. **Popular stops**: Badge frequently used stops
5. **Search stops**: Filter/search landmarks by name
6. **Stop photos**: Add images to landmark details
7. **Real-time info**: Show how many passengers waiting at stop

### Accessibility
- Consider adding voice-over descriptions
- Haptic feedback on tap
- Larger tap targets for accessibility mode
- High contrast mode support

## Testing Checklist

- [ ] Dots render correctly on map
- [ ] Tap opens bottom sheet with correct info
- [ ] "Set as unload point" only shows when valid
- [ ] Validation prevents setting unload before pickup
- [ ] Unload point updates correctly when landmark selected
- [ ] Map updates with new unload pin
- [ ] Booking form reflects landmark selection
- [ ] Works on different screen sizes
- [ ] Performance with many landmarks (50+ stops)
- [ ] Dots visible on different map zoom levels

## Code Files Modified

- `parago_passenger/lib/screens/passenger/passenger_home_screen.dart`
  - Modified `_routeLandmarkMarkers()` method
  - Added `_showLandmarkDetails()` method
  - Changed marker from labeled pin to numbered dot
  - Added tap gesture handling
  - Added bottom sheet UI for landmark details

## Related Features

This change integrates with:
- **Pickup/Unload Pin System**: Landmarks can set unload points
- **Route Validation**: Ensures unload comes after pickup
- **Fare Estimation**: Uses landmark positions for fare calculation
- **Booking Flow**: Landmark selection populates booking form
