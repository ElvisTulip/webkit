/*
 * Copyright (C) 2001 Apple Computer, Inc.  All rights reserved.
 *
 * Redistribution and use in source and binary forms, with or without
 * modification, are permitted provided that the following conditions
 * are met:
 * 1. Redistributions of source code must retain the above copyright
 *    notice, this list of conditions and the following disclaimer.
 * 2. Redistributions in binary form must reproduce the above copyright
 *    notice, this list of conditions and the following disclaimer in the
 *    documentation and/or other materials provided with the distribution.
 *
 * THIS SOFTWARE IS PROVIDED BY APPLE COMPUTER, INC. ``AS IS'' AND ANY
 * EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE
 * IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR
 * PURPOSE ARE DISCLAIMED.  IN NO EVENT SHALL APPLE COMPUTER, INC. OR
 * CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL,
 * EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO,
 * PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR
 * PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY
 * OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 * (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
 * OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE. 
 */

#include <kdebug.h>

    
kdbgstream::kdbgstream(unsigned int area, unsigned int level, bool print=true)
{
}
   

kdbgstream &kdbgstream::operator<<(int)
{
}


kdbgstream &kdbgstream::operator<<(const char *)
{
}


kdbgstream &kdbgstream::operator<<(const void *)
{
}


kdbgstream &kdbgstream::operator<<(const QString &)
{
}


kdbgstream &kdbgstream::operator<<(const QCString &)
{
}


kdbgstream &kdbgstream::operator<<(KDBGFUNC)
{
}




kdbgstream kdDebug(int area = 0)
{
}


kdbgstream kdWarning(int area = 0)
{
}


kdbgstream kdWarning(bool cond, int area = 0)
{
}


kdbgstream kdError(int area = 0)
{
}


kdbgstream kdError(bool cond, int area = 0)
{
}


kdbgstream kdFatal(int area = 0)
{
}


kdbgstream kdFatal(bool cond, int area = 0)
{
}



