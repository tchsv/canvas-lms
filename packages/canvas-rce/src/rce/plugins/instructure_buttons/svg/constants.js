/*
 * Copyright (C) 2021 - present Instructure, Inc.
 *
 * This file is part of Canvas.
 *
 * Canvas is free software: you can redistribute it and/or modify it under
 * the terms of the GNU Affero General Public License as published by the Free
 * Software Foundation, version 3 of the License.
 *
 * Canvas is distributed in the hope that it will be useful, but WITHOUT ANY
 * WARRANTY; without even the implied warranty of MERCHANTABILITY or FITNESS FOR
 * A PARTICULAR PURPOSE. See the GNU Affero General Public License for more
 * details.
 *
 * You should have received a copy of the GNU Affero General Public License along
 * with this program. If not, see <http://www.gnu.org/licenses/>.
 */

export const TYPE = 'image/svg+xml-icon-maker-icons'

export const Size = {
  None: 'none',
  ExtraSmall: 'x-small',
  Small: 'small',
  Medium: 'medium',
  Large: 'large',
  ExtraLarge: 'x-large'
}

export const DEFAULT_SETTINGS = {
  // Basic button & icon settings
  type: TYPE,
  alt: '',
  shape: 'square',
  size: Size.Small,
  color: null,
  outlineColor: '#000000',
  outlineSize: Size.None,
  text: '',
  textSize: Size.Small,
  textColor: '#000000',
  textBackgroundColor: null,
  textPosition: 'middle',
  encodedImage: '',
  encodedImageType: '',
  encodedImageName: '',
  // Embedded image crop settings
  x: 0,
  y: 0,
  translateX: 0,
  translateY: 0,
  width: 0,
  height: 0,
  transform: ''
}

export const DEFAULT_OPTIONS = {
  isPreview: false
}

export const BASE_SIZE = {
  [Size.ExtraSmall]: 74,
  [Size.Small]: 122,
  [Size.Medium]: 158,
  [Size.Large]: 218
}

export const STROKE_WIDTH = {
  [Size.None]: 0,
  [Size.Small]: 2,
  [Size.Medium]: 4,
  [Size.Large]: 8
}

export const TEXT_SIZE = {
  [Size.Small]: 14,
  [Size.Medium]: 16,
  [Size.Large]: 22,
  [Size.ExtraLarge]: 28
}

export const MAX_CHAR_COUNT = {
  [Size.Small]: 21,
  [Size.Medium]: 18,
  [Size.Large]: 13,
  [Size.ExtraLarge]: 10
}

export const MAX_TOTAL_TEXT_CHARS = 32

export const TEXT_BACKGROUND_PADDING = 4
