/*
    RawUnravel - rawunravel-Bridging-Header.h
    ----------------------------------------
    Copyright (C) 2025 Richard Barber

    This file is part of RawUnravel.

    RawUnravel is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    RawUnravel is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with RawUnravel.  If not, see <https://www.gnu.org/licenses/>.
*/

// MARK: - Bridging Header

// This bridging header exposes Objective-C interfaces to Swift.
// Swift code cannot import Objective-C++ (.mm) directly, so any
// Objective-C headers that declare public APIs for use in Swift
// must be included here.

// Only include what you actually need in Swift (minimal surface area).
// For example, RTPreviewDecoder is used in Swift to request RAW
// previews from the Objective-C++ implementation.

#import "RTPreviewDecoder.h"
