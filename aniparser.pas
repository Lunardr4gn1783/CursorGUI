unit AniParser;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils;

// By declaring this here in the 'interface' section,
// your Main Form (Unit1) is allowed to see and call this function.
function ParseAniMetadata(const FilePath: string): string;

implementation

// ==========================================
// BINARY BLUEPRINTS (Packed Records)
// ==========================================

type
  // The blueprint for every generic chunk inside a RIFF file
  TRiffChunkHeader = packed record
    ChunkID: array[0..3] of AnsiChar; // e.g., 'anih', 'LIST', 'rate'
    ChunkSize: Cardinal;              // How many bytes are in this chunk
  end;

  // The blueprint for the Animation Header payload
  TAniHeader = packed record
    cbSizeOf: Cardinal;   // Size of this structure (usually 36 bytes)
    cFrames: Cardinal;    // Total number of unique frames
    cSteps: Cardinal;     // Total number of animation steps
    cx, cy: Cardinal;     // Width and Height (often 0)
    cBitCount: Cardinal;  // Color depth
    cPlanes: Cardinal;    // Number of color planes
    JifRate: Cardinal;    // Default speed (1 Jiff = 1/60th of a second)
    Flags: Cardinal;      // 1 = Contains raw data, 2 = Uses a sequence array
  end;

// ==========================================
// PARSING ENGINE
// ==========================================

function ParseAniMetadata(const FilePath: string): string;
var
  FS: TFileStream;
  Signature, FormType: array[0..3] of AnsiChar;
  FileSize: Cardinal;
  Chunk: TRiffChunkHeader;
  AniHdr: TAniHeader;
  ExtractedInfo: string;
begin
  Result := 'Failed to parse file.';
  ExtractedInfo := '';

  // Open the file in raw, read-only binary mode
  FS := TFileStream.Create(FilePath, fmOpenRead or fmShareDenyWrite);
  try
    // 1. Read the main RIFF Header (12 bytes total)
    FS.ReadBuffer(Signature, 4);
    FS.ReadBuffer(FileSize, 4);
    FS.ReadBuffer(FormType, 4);

    // Verify this is actually an animated cursor
    if (Signature <> 'RIFF') or (FormType <> 'ACON') then
    begin
      Result := 'Error: Not a valid .ani file!';
      Exit;
    end;

    ExtractedInfo := 'Valid ACON file found.' + sLineBreak;

    // 2. Loop through the file, jumping from chunk to chunk
    while FS.Position < FS.Size do
    begin
      // Read the next chunk's ID and Size (8 bytes)
      FS.ReadBuffer(Chunk, SizeOf(TRiffChunkHeader));

      if Chunk.ChunkID = 'anih' then
      begin
        // We found the Animation Header! Read the metadata payload.
        FS.ReadBuffer(AniHdr, SizeOf(TAniHeader));

        ExtractedInfo := ExtractedInfo + 'Frames: ' + IntToStr(AniHdr.cFrames) + sLineBreak;
        ExtractedInfo := ExtractedInfo + 'Steps: ' + IntToStr(AniHdr.cSteps) + sLineBreak;
        ExtractedInfo := ExtractedInfo + 'Default Speed: ' + IntToStr(AniHdr.JifRate) + ' jiffs' + sLineBreak;

        // Skip any leftover padding bytes if the chunk is larger than our record
        FS.Position := FS.Position + (Chunk.ChunkSize - SizeOf(TAniHeader));
      end
      else if Chunk.ChunkID = 'LIST' then
      begin
        // This chunk contains the actual image data payload
        ExtractedInfo := ExtractedInfo + 'Found LIST payload chunk (' + IntToStr(Chunk.ChunkSize) + ' bytes).' + sLineBreak;
        FS.Position := FS.Position + Chunk.ChunkSize;
      end
      else
      begin
        // If we hit a chunk we don't care about (like 'rate' or 'seq '), skip it.
        FS.Position := FS.Position + Chunk.ChunkSize;
      end;

      // RIFF File Rule: Chunks MUST be word-aligned.
      // If a chunk's size is an odd number, we must jump over the invisible 1-byte padding.
      if (Chunk.ChunkSize mod 2) <> 0 then
        FS.Position := FS.Position + 1;
    end;

    Result := ExtractedInfo;

  finally
    // Always free the file stream so Windows doesn't lock the file!
    FS.Free;
  end;
end;

end.
