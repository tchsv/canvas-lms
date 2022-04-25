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

import fetchMock from 'fetch-mock'
import {renderHook, act} from '@testing-library/react-hooks/dom'
import {useSvgSettings, svgFromUrl, statuses} from '../settings'
import Editor from '../../../shared/__tests__/FakeEditor'
import RceApiSource from '../../../../../rcs/api'

jest.mock('../../../../../rcs/api')

describe('useSvgSettings()', () => {
  let editing, ed, rcs

  beforeEach(() => {
    ed = new Editor()
    rcs = {
      getFile: jest.fn(() => Promise.resolve({name: 'Test Button.svg'})),
      contextType: 'course',
      contextId: 1,
      canvasUrl: 'https://domain.from.env'
    }
    RceApiSource.mockImplementation(() => rcs)
  })

  afterEach(() => RceApiSource.mockClear())

  const subject = () => renderHook(() => useSvgSettings(ed, editing, rcs)).result

  describe('when a new button is being created (not editing)', () => {
    beforeEach(() => {
      editing = false
      global.fetch = jest.fn()
    })

    afterEach(() => jest.restoreAllMocks())

    it('initializes settings to the default', () => {
      const [settings, ,] = subject().current

      expect(settings).toEqual({
        type: 'image/svg+xml-icon-maker-icons',
        alt: '',
        shape: 'square',
        size: 'small',
        color: null,
        encodedImage: '',
        encodedImageType: '',
        encodedImageName: '',
        outlineColor: '#000000',
        outlineSize: 'none',
        text: '',
        textSize: 'small',
        textColor: '#000000',
        textBackgroundColor: null,
        textPosition: 'middle',
        x: 0,
        y: 0,
        translateX: 0,
        translateY: 0,
        width: 0,
        height: 0,
        transform: ''
      })
    })

    it('sets status to "IDLE"', () => {
      const [, status] = subject().current

      expect(status).toEqual(statuses.IDLE)
    })

    it('does not attempt to fetch an existing SVG', () => {
      expect(global.fetch).not.toHaveBeenCalled()
    })

    it('returns dispatch', () => {
      const [, , dispatch] = subject().current

      expect(typeof dispatch).toEqual('function')
    })

    describe('and a setting update action is dispatched', () => {
      let settingsUpdate

      beforeEach(() => (settingsUpdate = {name: 'Banana', size: 'large'}))

      it('updates the relevant settings', async () => {
        const result = subject()
        act(() => result.current[2](settingsUpdate))
        expect(result.current[0]).toEqual({
          type: 'image/svg+xml-icon-maker-icons',
          name: 'Banana',
          alt: '',
          shape: 'square',
          size: 'large',
          color: null,
          encodedImage: '',
          encodedImageType: '',
          encodedImageName: '',
          outlineColor: '#000000',
          outlineSize: 'none',
          text: '',
          textSize: 'small',
          textColor: '#000000',
          textBackgroundColor: null,
          textPosition: 'middle',
          x: 0,
          y: 0,
          translateX: 0,
          translateY: 0,
          width: 0,
          height: 0,
          transform: ''
        })
      })
    })
  })

  describe('when an existing button is being edited', () => {
    let mock
    let body

    beforeEach(() => {
      editing = true

      // Add an image to the editor and select it
      ed.setContent(
        '<img id="test-image" data-inst-icon-maker-icon="true" src="https://canvas.instructure.com/svg" data-download-url="https://canvas.instructure.com/files/1/download" alt="a red circle" />'
      )

      ed.setSelectedNode(ed.dom.select('#test-image')[0])

      //
      // NOTE: 'name' is no longer a valid property in embedded metadata
      // But we're leaving it here to test what happens with pre-existing
      // B&I that have it
      //
      body = `
        <svg height="100" width="100">
        <metadata>
          {
            "name":"Test Image",
            "alt":"a test image",
            "shape":"triangle",
            "size":"large",
            "color":"#FF2717",
            "outlineColor":"#06A3B7",
            "outlineSize":"small",
            "text":"Some Text",
            "textSize":"medium",
            "textColor":"#009606",
            "textBackgroundColor":"#06A3B7",
            "textPosition":"middle"
          }
        </metadata>
        <circle cx="50" cy="50" r="40" stroke="black" stroke-width="3" fill="red"/>
      </svg>`

      // Stub fetch to return an SVG file
      mock = fetchMock.mock({
        name: 'download-url',
        matcher: '*',
        response: () => ({body})
      })
    })

    afterEach(() => {
      jest.resetAllMocks()
      fetchMock.restore()
    })

    it('fetches the SVG file, specifying the course ID and timestamp', () => {
      subject()

      expect(mock.called('download-url')).toBe(true)
      expect(mock.calls('download-url')[0][0]).toMatch(
        /https:\/\/domain.from.env\/files\/1\/download\?replacement_chain_context_type=course&replacement_chain_context_id=1&ts=\d+&download_frd=1/
      )
    })

    describe('when the download URL contains a course ID', () => {
      beforeEach(() => {
        ed.setContent(
          '<img id="test-image" data-inst-icon-maker-icon="true" src="https://canvas.instructure.com/svg" data-download-url="courses/2/files/1/download" alt="a red circle" />'
        )
        ed.setSelectedNode(ed.dom.select('#test-image')[0])
      })

      it('fetches the SVG file using the /files/:file_id/download endpoint', () => {
        subject()

        expect(mock.called('download-url')).toBe(true)
        expect(mock.calls('download-url')[0][0]).toMatch(
          /https:\/\/domain.from.env\/files\/1\/download\?replacement_chain_context_type=course&replacement_chain_context_id=1&ts=\d+&download_frd=1/
        )
      })
    })

    describe('with a relative download URL', () => {
      beforeEach(() => {
        ed.setContent(
          '<img id="test-image" data-inst-icon-maker-icon="true" src="https://canvas.instructure.com/svg" data-download-url="/files/1/download" alt="a red circle" />'
        )
        ed.setSelectedNode(ed.dom.select('#test-image')[0])
      })

      it('fetches the SVG file, specifying the course ID and timestamp', () => {
        subject()
        const calledUrl = mock.calls('download-url')[0][0]
        expect(calledUrl).toMatch(
          /https:\/\/domain.from.env\/files\/1\/download\?replacement_chain_context_type=course&replacement_chain_context_id=1&ts=\d+&download_frd=1/
        )
      })
    })

    describe('with a containing element selected', () => {
      beforeEach(() => {
        ed.setContent(
          '<p id="containing"><img data-inst-icon-maker-icon="true" src="https://canvas.instructure.com/svg" data-download-url="/files/1/download" alt="a red circle" /></p>'
        )
        ed.setSelectedNode(ed.dom.select('#containing')[0])
      })

      it('fetches the SVG file, specifying the course ID and timestamp', () => {
        subject()
        const calledUrl = mock.calls('download-url')[0][0]
        expect(calledUrl).toMatch(
          /https:\/\/domain.from.env\/files\/1\/download\?replacement_chain_context_type=course&replacement_chain_context_id=1&ts=\d+&download_frd=1/
        )
      })
    })

    it('uses replacement chain context info in request for file name', async () => {
      const {result, waitForValueToChange} = renderHook(() => useSvgSettings(ed, editing, rcs))

      await waitForValueToChange(() => {
        return result.current[0]
      })

      expect(rcs.getFile).toHaveBeenCalledWith('1', {
        replacement_chain_context_id: 1,
        replacement_chain_context_type: 'course'
      })
    })

    it('parses the SVG settings from the SVG metadata', async () => {
      const {result, waitForValueToChange} = renderHook(() => useSvgSettings(ed, editing, rcs))

      await waitForValueToChange(() => {
        return result.current[0]
      })

      expect(result.current[0]).toEqual({
        type: 'image/svg+xml-icon-maker-icons',
        alt: 'a test image',
        shape: 'triangle',
        size: 'large',
        color: '#FF2717',
        encodedImage: '',
        encodedImageType: '',
        encodedImageName: '',
        outlineColor: '#06A3B7',
        outlineSize: 'small',
        text: 'Some Text',
        textSize: 'medium',
        textColor: '#009606',
        textBackgroundColor: '#06A3B7',
        textPosition: 'middle',
        x: 0,
        y: 0,
        translateX: 0,
        translateY: 0,
        width: 0,
        height: 0,
        name: 'Test Button',
        originalName: 'Test Button',
        transform: ''
      })
    })

    it('sets the status to "loading"', () => {
      const result = subject()
      expect(result.current[1]).toEqual(statuses.LOADING)
    })

    it('returns the status to "idle"', async () => {
      const {result, waitForValueToChange} = renderHook(() => useSvgSettings(ed, editing, rcs))

      await waitForValueToChange(() => {
        return result.current[1]
      })

      expect(result.current[1]).toEqual(statuses.IDLE)
    })

    describe('and the metadata is non-parsable', () => {
      body = `
        <svg height="100" width="100">
          <circle cx="50" cy="50" r="40" stroke="black" stroke-width="3" fill="red"/>
        </svg>
      `

      it('uses the default settings', () => {
        const result = subject()
        expect(result.current[0]).toEqual({
          type: 'image/svg+xml-icon-maker-icons',
          alt: '',
          shape: 'square',
          size: 'small',
          color: null,
          encodedImage: '',
          encodedImageType: '',
          encodedImageName: '',
          outlineColor: '#000000',
          outlineSize: 'none',
          text: '',
          textSize: 'small',
          textColor: '#000000',
          textBackgroundColor: null,
          textPosition: 'middle',
          x: 0,
          y: 0,
          translateX: 0,
          translateY: 0,
          width: 0,
          height: 0,
          transform: ''
        })
      })
    })

    describe('and the selected node has no src', () => {
      beforeEach(() => ed.setSelectedNode())

      it('uses the default settings', async () => {
        const result = subject()
        expect(result.current[0]).toEqual({
          type: 'image/svg+xml-icon-maker-icons',
          alt: '',
          shape: 'square',
          size: 'small',
          color: null,
          encodedImage: '',
          encodedImageType: '',
          encodedImageName: '',
          outlineColor: '#000000',
          outlineSize: 'none',
          text: '',
          textSize: 'small',
          textColor: '#000000',
          textBackgroundColor: null,
          textPosition: 'middle',
          x: 0,
          y: 0,
          translateX: 0,
          translateY: 0,
          width: 0,
          height: 0,
          transform: ''
        })
      })
    })
  })

  describe('when an existing button is edited while the tray is already open', () => {
    beforeEach(() => {
      editing = true

      // Add an image to the editor and select it
      ed.setContent(`
        <img id="test-image-1" src="https://canvas.instructure.com/svg1"
          data-inst-icon-maker-icon="true"
          data-download-url="https://canvas.instructure.com/files/1/download" />
        <img id="test-image-2" src="https://canvas.instructure.com/svg2"
          data-inst-icon-maker-icon="true"
          data-download-url="https://canvas.instructure.com/files/2/download" />
      `)

      fetchMock.mock('begin:https://domain.from.env/files/1/download', {
        body: `
          <svg height="100" width="100">
            <metadata>
              {
                "alt":"the first test image",
                "shape":"triangle",
                "size":"large",
                "color":"#FF2717",
                "outlineColor":"#06A3B7",
                "outlineSize":"small",
                "text":"Some Text",
                "textSize":"medium",
                "textColor":"#009606",
                "textBackgroundColor":"#06A3B7",
                "textPosition":"middle"
              }
            </metadata>
            <circle cx="50" cy="50" r="40" stroke="black" stroke-width="3" fill="red"/>
          </svg>`
      })

      fetchMock.mock('begin:https://domain.from.env/files/2/download', {
        body: `
          <svg height="100" width="100">
            <metadata>
              {
                "alt":"the second test image",
                "shape":"square",
                "size":"medium",
                "color":"#FF2717",
                "outlineColor":"#06A3B7",
                "outlineSize":"small",
                "text":"Some Text",
                "textSize":"medium",
                "textColor":"#009606",
                "textBackgroundColor":"#06A3B7",
                "textPosition":"middle"
              }
            </metadata>
            <circle cx="50" cy="50" r="40" stroke="black" stroke-width="3" fill="red"/>
          </svg>`
      })
    })

    afterEach(() => fetchMock.reset())

    it('loads the correct metadata', async () => {
      const {result, rerender, waitForValueToChange} = renderHook(() =>
        useSvgSettings(ed, editing, rcs)
      )

      ed.setSelectedNode(ed.dom.select('#test-image-1')[0])
      rerender()
      await waitForValueToChange(() => result.current)

      ed.setSelectedNode(ed.dom.select('#test-image-2')[0])
      rerender()
      await waitForValueToChange(() => result.current)

      expect(result.current[0].name).toEqual('Test Button')
      expect(result.current[0].shape).toEqual('square')
    })
  })
})

describe('svgFromUrl()', () => {
  let svgResponse

  const subject = () => svgFromUrl('https://www.instructure.com/svg')

  beforeEach(() => {
    fetchMock.mock('https://www.instructure.com/svg', () => ({
      body: svgResponse,
      sendAsJson: false
    }))
  })

  afterEach(() => {
    fetchMock.restore()
    jest.resetAllMocks()
  })

  describe('when the url points to an SVG file', () => {
    beforeEach(() => {
      svgResponse = `
        <svg height="100" width="100">
          <circle cx="50" cy="50" r="40" stroke="black" stroke-width="3" fill="red"/>
        </svg>
      `
    })

    it('returns the parsed SVG document', async () => {
      const svgDoc = await subject()
      expect(svgDoc.querySelector('svg').innerHTML).toContain(
        '<circle cx="50" cy="50" r="40" stroke="black" stroke-width="3" fill="red"/>'
      )
    })
  })

  describe('when the url points to a document that is not parsable', () => {
    beforeEach(() => (svgResponse = 'asdf'))

    it('returns an empty document', async () => {
      const doc = await subject()
      expect(doc.firstChild.toString.innerHTML).toEqual(undefined)
    })
  })
})
