;;; org-toggl.el --- A simple Org-mode interface to Toggl  -*- lexical-binding: t; -*-

;; Copyright (C) 2016  Marcin Borkowski

;; Author: Marcin Borkowski <mbork@mbork.pl>
;; Keywords: calendar
;; Package-Requires: ((request "0.2.0"))

;; This file is NOT part of GNU Emacs.

;; This program is free software; you can redistribute it and/or modify
;; it under the terms of the GNU General Public License as published by
;; the Free Software Foundation, either version 3 of the License, or
;; (at your option) any later version.

;; This program is distributed in the hope that it will be useful,
;; but WITHOUT ANY WARRANTY; without even the implied warranty of
;; MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
;; GNU General Public License for more details.

;; You should have received a copy of the GNU General Public License
;; along with this program.  If not, see <http://www.gnu.org/licenses/>.

;;; Commentary:

;; A simple Org-mode interface to Toggl, a time-tracking service.
;; Hooks into the Org-mode's clocking mechanism.

;;; Code:

(require 'json)
(require 'request)

(defcustom toggl-auth-token ""
  "Authentication token for Toggl."
  :type 'string
  :group 'toggl)

(defcustom toggl-default-timeout 20
  "Default timeout for HTTP requests."
  :type 'integer
  :group 'toggl)

;; FIXME change this to name and get the id in `toggl-get-projects'
(defcustom toggl-workspace-id nil
  "Toggl workspace id.
Can be looked up in the URL.  Click \"manage workspaces\" and
select the workspace - the number after `/workspaces/` is the
workspace id."
  :type 'integer
  :group 'toggl)

(defvar toggl-api-url "https://api.track.toggl.com/api/v9/"
  "The URL for making API calls.")

(defun toggl-create-api-url (string)
  "Prepend Toogl API URL to STRING."
  (concat toggl-api-url string))

(defun toggl-prepare-auth-header ()
  "Return a cons to be put into headers for authentication."
  (cons "Authorization"
	(format "Basic %s" (base64-encode-string (concat toggl-auth-token ":api_token")))))

(defun toggl-request-get (request &optional sync success-fun error-fun timeout)
  "Send a GET REQUEST to toggl.com, with TIMEOUT.
Add the auth token)."
  (request (toggl-create-api-url request)
	   :parser #'json-read
	   :headers (list (toggl-prepare-auth-header))
	   :success success-fun
	   :error error-fun
	   :sync sync
	   :timeout (or timeout toggl-default-timeout)))

(defun toggl-request-post (request data &optional sync success-fun error-fun timeout)
  "Send a GET REQUEST to toggl.com, with TIMEOUT.
Add the auth token)."
  (request (toggl-create-api-url request)
	   :type "POST"
	   :data data
	   :parser #'json-read
	   :headers (list (toggl-prepare-auth-header)
			  '("Content-Type" . "application/json"))
	   :success success-fun
	   :error error-fun
	   :sync sync
	   :timeout (or timeout toggl-default-timeout)))

(defun toggl-request-put (request data &optional sync success-fun error-fun timeout)
  "Send a GET REQUEST to toggl.com, with TIMEOUT.
Add the auth token)."
  (request (toggl-create-api-url request)
    :type "PUT"
    :data data
    :parser #'json-read
    :headers (list (toggl-prepare-auth-header)
		   '("Content-Type" . "application/json"))
    :success success-fun
    :error error-fun
    :sync sync
    :timeout (or timeout toggl-default-timeout)))

(defun toggl-request-patch (request data &optional sync success-fun error-fun timeout)
  "Send a PATCH REQUEST to toggl.com, with TIMEOUT.
Add the auth token)."
  (request (toggl-create-api-url request)
	   :type "PATCH"
	   :data data
	   :parser #'json-read
	   :headers (list (toggl-prepare-auth-header)
			  '("Content-Type" . "application/json"))
	   :success success-fun
	   :error error-fun
	   :sync sync
	   :timeout (or timeout toggl-default-timeout)))

(defun toggl-request-delete (request &optional sync success-fun error-fun timeout)
  "Send a DELETE REQUEST to toggl.com, with TIMEOUT.
Add the auth token)."
  (request (toggl-create-api-url request)
	   :type "DELETE"
	   ;; :parser #'buffer-string
	   :headers (list (toggl-prepare-auth-header))
	   :success success-fun
	   :error error-fun
	   :sync sync
	   :timeout (or timeout toggl-default-timeout)))

(defvar toggl-projects nil
  "A list of available projects.
Each project is a cons cell with car equal to its name and cdr to
its id.")

(defvar toggl-current-time-entry nil
  "Data of the current Toggl time entry.")

(defun toggl-get-projects ()
  "Fill in `toggl-projects' (asynchronously)."
  (interactive)
  (toggl-request-get
   "me?with_related_data=true"
   nil
   (cl-function
    (lambda (&key data &allow-other-keys)
      (setq toggl-projects
	    (mapcar (lambda (project)
		      (cons (substring-no-properties (alist-get 'name project))
			    (alist-get 'id project)))
		    (alist-get 'projects data)))
      (message "Toggl projects successfully downloaded.")))
   (cl-function
    (lambda (&key error-thrown &allow-other-keys)
      (message "Fetching projects failed because %s" error-thrown)))))

(defvar toggl-default-project nil
  "Id of the default Toggl project.")

(defun toggl-select-default-project (project)
  "Make PROJECT the default.
It is assumed that no two projects have the same name."
  (interactive (list (completing-read "Default project: " toggl-projects nil t)))
  (setq toggl-default-project (toggl-get-pid project)))

(defun toggl-start-time-entry (description &optional pid show-message)
  "Start Toggl time entry."
  (interactive "MDescription: \ni\np")
  (setq pid (or pid toggl-default-project))
  (toggl-request-post
   (format "workspaces/%s/time_entries" toggl-workspace-id)
   (json-encode `(("description" . ,description)
		  ("duration" . -1)
		  ("project_id" . ,pid)
		  ("created_with" . "mbork's Emacs toggl client")
		  ("start" . ,(format-time-string "%FT%TZ" nil t))
		  ("workspace_id" . ,toggl-workspace-id)))
   nil
   (cl-function
    (lambda (&key data &allow-other-keys)
      (setq toggl-current-time-entry data)
      (when show-message (message "Toggl time entry started."))))
   (cl-function
    (lambda (&key error-thrown &allow-other-keys)
      (when show-message (message "Starting time entry failed because %s" error-thrown))))))

(defun toggl-stop-time-entry (&optional show-message)
  "Stop running Toggl time entry."
  (interactive "p")
  (when toggl-current-time-entry
    (let ((time-entry-id (alist-get 'id toggl-current-time-entry)))
      (toggl-request-patch
       (format "workspaces/%s/time_entries/%s/stop"
	       toggl-workspace-id
	       time-entry-id)
       (json-encode `(("time_entry_id" . ,time-entry-id)
		      ("workspace_id" . ,toggl-workspace-id)))
       nil
       (cl-function
	(lambda (&key data &allow-other-keys)
	  (when show-message (message "Toggl time entry stopped."))))
       (cl-function
	(lambda (&key error-thrown &allow-other-keys)
	  (when show-message (message "Stopping time entry failed because %s" error-thrown))))))
    (setq toggl-current-time-entry nil)))

(defun toggl-delete-time-entry (&optional tid show-message)
  "Delete a Toggl time entry.
By default, delete the current one."
  (interactive "ip")
  (when toggl-current-time-entry
    (setq tid (or tid (alist-get 'id toggl-current-time-entry)))
    (toggl-request-delete
     (format "workspaces/%s/time_entries/%s" toggl-workspace-id tid)
     nil
     (cl-function
      (lambda (&key data &allow-other-keys)
	(when (= tid (alist-get 'id toggl-current-time-entry))
	  (setq toggl-current-time-entry nil))
	(when show-message (message "Toggl time entry deleted."))))
     (cl-function
      (lambda (&key error-thrown &allow-other-keys)
	(when show-message (message "Deleting time entry failed because %s" error-thrown)))))))

(defun toggl-get-pid (project)
  "Get PID given PROJECT's name."
  (cdr (assoc project toggl-projects)))

(defcustom org-toggl-inherit-toggl-properties nil
  "Make org-toggl use property inheritance."
  :type 'boolean
  :group 'toggl)

(defun org-toggl-clock-in ()
  "Start a Toggl time entry based on current heading."
  (interactive)
  (let* ((heading (substring-no-properties (org-get-heading t t t t)))
	 (project (org-entry-get (point) "toggl-project" org-toggl-inherit-toggl-properties))
	 (pid (toggl-get-pid project)))
    (if pid
        (toggl-start-time-entry heading pid t)
      (toggl-start-time-entry heading nil t))))

(defun org-toggl-clock-out ()
  "Stop the running Toggle time entry."
  (toggl-stop-time-entry t))

(defun org-toggl-clock-cancel ()
  "Delete the running Toggle time entry."
  (toggl-delete-time-entry nil t))

(defun org-toggl-set-project (project)
  "Save PROJECT in the properties of the current Org headline."
  (interactive (list (completing-read "Toggl project for this headline: " toggl-projects nil t))) ; TODO: dry!
  (org-set-property "toggl-project" project))

(defun org-toggl-submit-clock-at-point (&optional show-message)
  "Submit the clock entry at point to Toggl."
  (interactive "p")
  (let ((element (org-element-at-point)))
    (if (eq (org-element-type element) 'clock)
	(let* ((heading (substring-no-properties (org-get-heading t t t t)))
	       (project (org-entry-get (point) "toggl-project" org-toggl-inherit-toggl-properties))
	       (pid (or (toggl-get-pid project) toggl-default-project))
	       (timestamp (org-element-property :value element))
	       (year-start (org-element-property :year-start timestamp))
	       (month-start (org-element-property :month-start timestamp))
	       (day-start (org-element-property :day-start timestamp))
	       (hour-start (org-element-property :hour-start timestamp))
	       (minute-start (org-element-property :minute-start timestamp))
	       (year-end (org-element-property :year-end timestamp))
	       (month-end (org-element-property :month-end timestamp))
	       (day-end (org-element-property :day-end timestamp))
	       (hour-end (org-element-property :hour-end timestamp))
	       (minute-end (org-element-property :minute-end timestamp))
	       (start-time (time-to-seconds (encode-time
					     0
					     minute-start
					     hour-start
					     day-start
					     month-start
					     year-start)))
	       (stop-time (time-to-seconds (encode-time
					    0
					    minute-end
					    hour-end
					    day-end
					    month-end
					    year-end))))
	  (toggl-request-post
     (format "workspaces/%s/time_entries" toggl-workspace-id)
     (json-encode `(("description" . ,heading)
		    ("project_id" . ,pid)
		    ("created_with" . "mbork's Emacs toggl client")
		    ("start" . ,(format-time-string "%FT%TZ" start-time t))
		    ("stop" . ,(format-time-string "%FT%TZ" stop-time t))
		    ("workspace_id" . ,toggl-workspace-id)))
     nil
     (cl-function
      (lambda (&key data &allow-other-keys)
	(setq toggl-current-time-entry data)
	(when show-message (message "Toggl time entry submitted."))))
     (cl-function
      (lambda (&key error-thrown &allow-other-keys)
	(when show-message (message "Starting time entry failed because %s" error-thrown))))))
      (error "No clock at point"))))

(define-minor-mode org-toggl-integration-mode
  "Toggle a (global) minor mode for Org/Toggl integration.
When on, clocking in and out starts and stops Toggl time entries
automatically."
  :init-value nil
  :global t
  :lighter " T-O"
  (if org-toggl-integration-mode
      (progn
	(add-hook 'org-clock-in-hook #'org-toggl-clock-in)
	(add-hook 'org-clock-out-hook #'org-toggl-clock-out)
	(add-hook 'org-clock-cancel-hook #'org-toggl-clock-cancel))
    (remove-hook 'org-clock-in-hook #'org-toggl-clock-in)
    (remove-hook 'org-clock-out-hook #'org-toggl-clock-out)
    (remove-hook 'org-clock-cancel-hook #'org-toggl-clock-cancel)))

(provide 'org-toggl)
;;; org-toggl.el ends here
