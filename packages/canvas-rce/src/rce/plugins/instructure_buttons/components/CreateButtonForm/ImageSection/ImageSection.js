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

import React, {useReducer, useEffect, Suspense, useRef, useCallback} from 'react'

import formatMessage from '../../../../../../format-message'
import reducer, {actions, initialState, modes} from '../../../reducers/imageSection'
import {actions as svgActions} from '../../../reducers/svgSettings'

import {Flex} from '@instructure/ui-flex'
import {Group} from '../Group'
import {Spinner} from '@instructure/ui-spinner'
import {Text} from '@instructure/ui-text'

import Course from './Course'
import {ImageOptions} from './ImageOptions'
import {ColorInput} from '../../../../shared/ColorInput'
import {convertFileToBase64} from '../../../svg/utils'
import {transformForShape} from '../../../svg/image'

const getColorSection = () => document.querySelector('#buttons-tray-color-section')

export const ImageSection = ({settings, onChange, editing, editor, rcsConfig}) => {
  const [state, dispatch] = useReducer(reducer, initialState)
  const bottomRef = useRef()

  const scrollToBottom = useCallback(() => {
    if (!bottomRef.current?.scrollIntoView) return
    if (state.scrolled) return

    bottomRef.current.scrollIntoView({behavior: 'smooth'})
    dispatch({...actions.SET_SCROLLED, payload: true})
  })

  const Upload = React.lazy(() => import('./Upload'))
  const SingleColor = React.lazy(() => import('./SingleColor'))
  const MultiColor = React.lazy(() => import('./MultiColor'))

  // This object maps image selection modes to the
  // component that handles that selection.
  //
  // The selected component is dynamically rendered
  // in this component's returned JSX
  const allowedModes = {
    [modes.courseImages.type]: Course,
    [modes.uploadImages.type]: Upload,
    [modes.singleColorImages.type]: SingleColor,
    [modes.multiColorImages.type]: MultiColor
  }

  useEffect(() => {
    const transform = transformForShape(settings.shape, settings.size)

    // Set Q1 crop defaults
    // TODO: Set these properties based on cropper
    onChange({
      type: svgActions.SET_X,
      payload: transform.x
    })

    onChange({
      type: svgActions.SET_Y,
      payload: transform.y
    })

    onChange({
      type: svgActions.SET_WIDTH,
      payload: transform.width
    })

    onChange({
      type: svgActions.SET_HEIGHT,
      payload: transform.height
    })

    onChange({
      type: svgActions.SET_TRANSLATE_X,
      payload: transform.translateX
    })

    onChange({
      type: svgActions.SET_TRANSLATE_Y,
      payload: transform.translateY
    })
  }, [onChange, settings.shape, settings.size])

  useEffect(() => {
    if (editing && !!settings.encodedImage) {
      dispatch({
        type: actions.SET_IMAGE.type,
        payload: settings.encodedImage
      })
    }
  }, [editing, settings.encodedImage])

  useEffect(() => {
    if (editing && !!settings.encodedImageName) {
      dispatch({
        type: actions.SET_IMAGE_NAME.type,
        payload: settings.encodedImageName
      })
    }
  }, [editing, settings.encodedImageName])

  useEffect(() => {
    onChange({
      type: svgActions.SET_ENCODED_IMAGE,
      payload: state.image
    })
  }, [onChange, state.image])

  useEffect(() => {
    onChange({
      type: svgActions.SET_ENCODED_IMAGE_TYPE,
      payload: state.mode
    })
  }, [onChange, state.mode])

  useEffect(() => {
    onChange({
      type: svgActions.SET_ENCODED_IMAGE_NAME,
      payload: state.imageName
    })
  }, [onChange, state.imageName])

  useEffect(() => {
    if (state.icon) {
      dispatch({...actions.START_LOADING})
      // eslint-disable-next-line promise/catch-or-return
      convertFileToBase64(
        new Blob([state.icon.source(state.iconFillColor)], {
          type: 'image/svg+xml'
        })
      ).then(base64Image => {
        dispatch({...actions.SET_IMAGE, payload: base64Image})
        dispatch({...actions.STOP_LOADING})
      })
    }
  }, [state.icon, state.iconFillColor])

  const modeIsAllowed = !!allowedModes[state.mode]
  const ImageSelector = allowedModes[state.mode]

  return (
    <Group as="section" defaultExpanded summary={formatMessage('Image')}>
      <Flex
        as="section"
        justifyItems="space-between"
        direction="column"
        id="buttons-tray-text-section"
      >
        <Flex.Item>
          <Flex direction="column">
            <Flex.Item padding="small 0 0 small">
              <Text weight="bold">{formatMessage('Current Image')}</Text>
            </Flex.Item>
            <Flex.Item>
              <ImageOptions state={state} dispatch={dispatch} rcsConfig={rcsConfig} />
            </Flex.Item>
          </Flex>
        </Flex.Item>
        <Suspense
          fallback={
            <Flex justifyItems="center">
              <Flex.Item>
                <Spinner renderTitle={formatMessage('Loading')} />
              </Flex.Item>
            </Flex>
          }
        >
          {modeIsAllowed && state.collectionOpen && (
            <Flex.Item padding="small">
              <ImageSelector
                dispatch={dispatch}
                editor={editor}
                data={state}
                onMount={scrollToBottom}
              />
            </Flex.Item>
          )}
        </Suspense>
        {state.icon && state.mode === modes.singleColorImages.type && (
          <Flex.Item padding="small">
            <ColorInput
              color={state.iconFillColor}
              label={formatMessage('Single Color Image Color')}
              name="single-color-image-fill"
              onChange={color => dispatch({type: actions.SET_ICON_FILL_COLOR.type, payload: color})}
              popoverMountNode={getColorSection}
            />
          </Flex.Item>
        )}
      </Flex>
      <span ref={bottomRef}></span>
    </Group>
  )
}
