/*
 * Copyright (C) 2022 - present Instructure, Inc.
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

import SentryFullStory from '@sentry/fullstory'
import {configureScope, init} from '@sentry/react'
import {Integration} from '@sentry/types'
import {BrowserTracing} from '@sentry/tracing'

export function initSentry() {
  const sentrySettings = ENV.SENTRY_FRONTEND

  // Initialize Sentry as early as possible
  if (sentrySettings?.dsn) {
    const errorsSampleRate = parseFloat(sentrySettings.errors_sample_rate) || 0.0
    const tracesSampleRate = parseFloat(sentrySettings.traces_sample_rate) || 0.0
    const integrations: Integration[] = []
    const denyUrls = sentrySettings.url_deny_pattern
      ? [new RegExp(sentrySettings.url_deny_pattern)]
      : undefined

    if (ENV.FULL_STORY_ENABLED) {
      integrations.push(
        new SentryFullStory(sentrySettings.org_slug, {baseSentryUrl: sentrySettings.base_url})
      )
    }

    if (tracesSampleRate) integrations.push(new BrowserTracing() as Integration)

    init({
      dsn: sentrySettings.dsn,
      environment: sentrySettings.environment,
      release: sentrySettings.revision,

      denyUrls,
      integrations,

      sampleRate: errorsSampleRate,
      tracesSampleRate,

      initialScope: {
        tags: {k12: ENV.k12, k5_user: ENV.K5_USER, student_user: ENV.current_user_is_student},
        user: {id: ENV.current_user_global_id}
      }
    })

    if (sentrySettings.normalized_route)
      configureScope(scope => scope.setTransactionName(sentrySettings.normalized_route))
  }
}
