/*
 * Copyright (C) 2011 Google Inc.  All rights reserved.
 * Copyright (C) 2007, 2008, 2013 Apple Inc.  All rights reserved.
 * Copyright (C) 2009 Joseph Pecoraro
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 *
 * 1.  Redistributions of source code must retain the above copyright
 *     notice, this list of conditions and the following disclaimer.
 * 2.  Redistributions in binary form must reproduce the above copyright
 *     notice, this list of conditions and the following disclaimer in the
 *     documentation and/or other materials provided with the distribution.
 * 3.  Neither the name of Apple Inc. ("Apple") nor the names of
 *     its contributors may be used to endorse or promote products derived
 *     from this software without specific prior written permission.
 *
 * THIS SOFTWARE IS PROVIDED BY APPLE AND ITS CONTRIBUTORS "AS IS" AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 * WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 * DISCLAIMED. IN NO EVENT SHALL APPLE OR ITS CONTRIBUTORS BE LIABLE FOR ANY
 * DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 * (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 * LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 * ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF
 * THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

WebInspector.LegacyConsoleMessage = function(source, level, url, line, column, repeatCount)
{
    this.source = source;
    this.level = level;
    this.url = url || null;
    this.line = line || 0;
    this.column = column || 0;

    repeatCount = repeatCount || 1;
    this.repeatCount = repeatCount;
    this.repeatDelta = repeatCount;
    this.totalRepeatCount = repeatCount;
};

WebInspector.LegacyConsoleMessage.prototype = {
    isErrorOrWarning: function()
    {
        return (this.level === WebInspector.LegacyConsoleMessage.MessageLevel.Warning || this.level === WebInspector.LegacyConsoleMessage.MessageLevel.Error);
    },

    updateRepeatCount: function()
    {
        // Implemented by concrete instances
    },

    clone: function()
    {
        // Implemented by concrete instances
    }
};

WebInspector.LegacyConsoleMessage.create = function(source, level, message, type, url, line, column, repeatCount, parameters, stackTrace, request)
{
    return new WebInspector.LegacyConsoleMessageImpl(source, level, message, null, type, url, line, column, repeatCount, parameters, stackTrace, request);
};

// FIXME: Switch to ConsoleAgent.ConsoleMessageSource.
WebInspector.LegacyConsoleMessage.MessageSource = {
    HTML: "html",
    XML: "xml",
    JS: "javascript",
    Network: "network",
    ConsoleAPI: "console-api",
    Other: "other"
};

// FIXME: Switch to ConsoleAgent.ConsoleMessageType.
WebInspector.LegacyConsoleMessage.MessageType = {
    Log: "log",
    Dir: "dir",
    DirXML: "dirxml",
    Table: "table",
    Trace: "trace",
    StartGroup: "startGroup",
    StartGroupCollapsed: "startGroupCollapsed",
    EndGroup: "endGroup",
    Assert: "assert",
    Result: "result"
};

// FIXME: Switch to ConsoleAgent.ConsoleMessageLevel.
WebInspector.LegacyConsoleMessage.MessageLevel = {
    Tip: "tip",
    Log: "log",
    Warning: "warning",
    Error: "error",
    Debug: "debug"
};
