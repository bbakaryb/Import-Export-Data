import { LightningElement, api, track } from 'lwc';
import getObjectApiNameFromRecordId from '@salesforce/apex/Import_Export_Data.getObjectApiNameFromRecordId';
import listFields from '@salesforce/apex/Import_Export_Data.listFields';
import exportCsv from '@salesforce/apex/Import_Export_Data.exportCsv';
import importCsv from '@salesforce/apex/Import_Export_Data.importCsv';
import { ShowToastEvent } from 'lightning/platformShowToastEvent';

export default class Lwc01_DataPorter extends LightningElement {

  @api recordId;
    selectedObject = '';
    fields = [];
    selectedFields = [];
    orderedFields = [];
    isLoading = false;
    message = '';

    // Preview
    previewHeaders = [];
    previewRows = [];
    showPreview = false;

    MAX_PREVIEW_ROWS = 10;


    /**
     * Initialize component:
     * - Detect object from recordId
     * - Load available CSV-compatible fields
     */
    connectedCallback() {
        if (this.recordId) {
            getObjectApiNameFromRecordId({ recordId: this.recordId })
                .then(objName => {
                    this.selectedObject = objName;
                    return listFields({ objectName: objName });
                })
                .then(flds => {
                    // Dual-listbox expects { label, value }
                    this.fields = flds.map(f => ({ label: f.label, value: f.api }));
                })
                .catch(err => {
                    this.message = 'Error: ' + (err.body ? err.body.message : err.message);
                });
        }
    }

    /**
     * Handle selection changes in the dual-listbox
     * Maintain field order and display labels instead of API names
     */
    handleFieldsChange(e) {
        this.selectedFields = e.detail.value;
        let newOrdered = [];

        // Map API name → label for quick lookup
        const labelByApi = new Map(
            this.fields.map(f => [f.value, f.label])
        );

        // Preserve previous order when possible
        for (let ofld of this.orderedFields) {
            if (this.selectedFields.includes(ofld.value)) newOrdered.push(ofld);
        }
        // Add newly selected fields at the end
        for (let f of this.selectedFields) {
            if (!newOrdered.find(x => x.value === f)) {
                newOrdered.push({ label: labelByApi.get(f), value: f, index: newOrdered.length });
            }
        }
        // Recalculate indexes
        this.orderedFields = newOrdered.map((f, i) => ({ ...f, index: i }));
    }

    /**
     * Swap two fields in the order list
     */
    swapOrder(i, j) {
        const tmp = this.orderedFields[i];
        this.orderedFields[i] = this.orderedFields[j];
        this.orderedFields[j] = tmp;
        this.orderedFields = this.orderedFields.map((f, idx) => ({ ...f, index: idx }));
    }

    /**
     * Move field up
     */
    moveUp(evt) {
        const idx = parseInt(evt.target.dataset.index, 10);
        if (idx > 0) this.swapOrder(idx, idx - 1);
    }

    /**
     * Move field down
     */
    moveDown(evt) {
        const idx = parseInt(evt.target.dataset.index, 10);
        if (idx < this.orderedFields.length - 1) this.swapOrder(idx, idx + 1);
    }

    /**
     * Remove field from selection
     */
    removeField(evt) {
        const idx = parseInt(evt.target.dataset.index, 10);
        this.orderedFields.splice(idx, 1);
        this.orderedFields = this.orderedFields.map((f, i) => ({ ...f, index: i }));
        this.selectedFields = this.orderedFields.map(f => f.value);
    }

    /**
     * Export records to CSV
     */
    async handleExport() {
        if (!this.selectedFields.length) {
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: 'Please select at least one field before exporting.',
                variant: 'error'
            }));
            return;
        }

        this.isLoading = true;
        try {
            const base64Data = await exportCsv({
                objectName: this.selectedObject,
                fields: this.selectedFields,
                recordId: this.recordId
            });

            const blobUrl = 'data:application/octet-stream;base64,' + base64Data;
            const link = document.createElement('a');
            link.href = blobUrl;
            link.download = `${this.selectedObject}_export.csv`;
            document.body.appendChild(link);
            link.click();
            document.body.removeChild(link);

            this.dispatchEvent(new ShowToastEvent({
                title: 'Success',
                message: 'CSV exported successfully',
                variant: 'success'
            }));
        } catch (error) {
            console.error(error);
            this.dispatchEvent(new ShowToastEvent({
                title: 'Error',
                message: error.body?.message || error.message,
                variant: 'error'
            }));
        } finally {
            this.isLoading = false;
        }
    }

    /**
     * Store selected CSV file
     */
    handleFileChange(event) {
        if (event.target.files.length === 0) {
            this.resetPreview();
            return;
        }

        this.file = event.target.files[0];

        const reader = new FileReader();
        reader.onload = () => {
            const text = reader.result;
            const preview = this.parseCsv(text);

            this.previewHeaders = preview.headers;
            this.previewRows = preview.rows;
            this.showPreview = true;
        };

        reader.readAsText(this.file);
    }

    resetPreview() {
        this.previewHeaders = [];
        this.previewRows = [];
        this.showPreview = false;
    }


    /**
     * Import CSV file into Salesforce
     */
    async handleImport() {
    if (!this.file) {
        alert('Selected CSV file.');
        return;
    }

    const reader = new FileReader();

    reader.onload = async () => {
        try {

            const arrayBuffer = reader.result;

            // Conversion ArrayBuffer → Base64 
            let binary = '';
            const bytes = new Uint8Array(arrayBuffer);
            const len = bytes.byteLength;

            for (let i = 0; i < len; i++) {
                binary += String.fromCharCode(bytes[i]);
            }

            const base64Data = btoa(binary);

            const result = await importCsv({
                objectName: this.selectedObject,
                base64Csv: base64Data
            });

            /* Validation errors */
            if (result.success === false) {
                const errorMessage =
                    result.errors && result.errors.length
                        ? result.errors.join('\n')
                        : 'Unknown CSV validation errors.';

                this.dispatchEvent(
                    new ShowToastEvent({
                        title: 'Import cancelled',
                        message: errorMessage,
                        variant: 'error',
                        mode: 'sticky'
                    })
                );
                return;
            }

            /* Success */
            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Import completed',
                    message: `${result.inserted} records imported successfully.`,
                    variant: 'success'
                })
            );

        } catch (error) {
            console.error(error);

            this.dispatchEvent(
                new ShowToastEvent({
                    title: 'Server error',
                    message: error.body ? error.body.message : error.message,
                    variant: 'error',
                    mode: 'sticky'
                })
            );
        }
    };

    reader.readAsArrayBuffer(this.file);
}

parseCsv(text) {
    const lines = text
        .replace(/\r\n/g, '\n')
        .replace(/\r/g, '\n')
        .split('\n')
        .filter(l => l.trim());

    if (!lines.length) {
        return { headers: [], rows: [] };
    }

    const parseLine = (line) => {
        const result = [];
        let current = '';
        let inQuotes = false;

        for (let i = 0; i < line.length; i++) {
            const c = line[i];

            if (c === '"') {
                if (inQuotes && line[i + 1] === '"') {
                    current += '"';
                    i++;
                } else {
                    inQuotes = !inQuotes;
                }
            } else if (c === ',' && !inQuotes) {
                result.push(current);
                current = '';
            } else {
                current += c;
            }
        }
        result.push(current);
        return result.map(v => v.replace(/^"|"$/g, '').trim());
    };

    const headers = parseLine(lines[0]);

    const rows = [];
    for (let i = 1; i < lines.length && rows.length < this.MAX_PREVIEW_ROWS; i++) {
        const values = parseLine(lines[i]);

        rows.push({
            _rowKey: i,
            cells: headers.map((h, idx) => ({
                key: h,
                value: values[idx] || ''
            }))
        });
    }

    return { headers, rows };
}





}