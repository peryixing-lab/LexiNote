import { common } from '@kit.AbilityKit';
import { fileIo as fs, picker } from '@kit.CoreFileKit';
import { pdfService } from '@kit.PDFKit';
import { NoteItem } from './LexiModels';

export class LexiExportService {
  static async saveBytes(context: common.UIAbilityContext, filename: string, bytes: ArrayBuffer): Promise<void> {
    const paths = await new picker.DocumentViewPicker(context).save({ newFileNames: [filename.replace(/[\\/:*?"<>|]/g, '_')] });
    if (!paths.length) { return; }
    const file = await fs.open(paths[0], fs.OpenMode.WRITE_ONLY | fs.OpenMode.TRUNC);
    try { await fs.write(file.fd, bytes); } finally { await fs.close(file); }
  }
  static async pdf(context: common.UIAbilityContext, note: NoteItem): Promise<void> {
    const document = new pdfService.PdfDocument();
    const path = context.cacheDir + '/lexi-export-' + Date.now() + '.pdf';
    try {
      if (!document.createDocument(595, 842)) { throw new Error('无法创建 PDF'); }
      const allRows: string[] = [];
      const style = new pdfService.TextStyle(); style.textSize = 12;
      const font = new pdfService.FontInfo(); font.fontName = 'HarmonyOS Sans SC'; style.fontInfo = font;
      for (const paragraph of (note.title + '\n\n' + note.content).split('\n')) {
        let line = ''; let units = 0;
        const rows: string[] = [];
        for (const character of paragraph) {
          const size = character.charCodeAt(0) > 255 ? 2 : 1;
          if (units + size > 78) { rows.push(line); line = ''; units = 0; }
          line += character; units += size;
        }
        rows.push(line);
        for (const row of rows) { allRows.push(row); }
      }
      const pageCount = Math.max(1, Math.ceil(allRows.length / 37));
      for (let index = 1; index < pageCount; index++) { document.insertBlankPage(0, 595, 842); }
      for (let index = 0; index < allRows.length; index++) {
        document.getPage(Math.floor(index / 37)).addTextObject(allRows[index], 48, 790 - (index % 37) * 20, style);
      }
      if (!document.saveDocument(path)) { throw new Error('PDF 保存失败'); }
      const file = fs.openSync(path, fs.OpenMode.READ_ONLY);
      const data = new ArrayBuffer(fs.statSync(path).size);
      try { fs.readSync(file.fd, data); } finally { fs.closeSync(file); }
      await LexiExportService.saveBytes(context, (note.title || '笔记') + '.pdf', data);
    } finally { document.releaseDocument(); if (fs.accessSync(path)) { fs.unlinkSync(path); } }
  }
}
