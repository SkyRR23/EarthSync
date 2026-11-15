# Laboratory report workflow

1. Choose **Laboratory report** in the farm photo screen; preview and confirm upload.
2. The sanitizer stores private pixels. If installed, local Tesseract runs with
   fixed stdin/stdout arguments, `--psm 6`, and a 20-second timeout.
3. The conservative line parser retains explicitly labeled sample/laboratory/date,
   depth/method and numeric measurements. Missing units stay missing; pH uses
   dimensionless `pH`, not a concentration. It does not calculate missing chemistry.
4. Open **Check, correct and confirm sample**. Inspect the authorized original
   image, correct the transcription and retain units, method, depth and locator.
   Select the explicit confirmation checkbox before submission.
5. The server retains original extraction separately from the latest confirmation,
   recording confirmation time and principal. This is a user-confirmed sample
   transcription; laboratory authenticity remains unverified.

Supported labeled numeric fields: pH, organic matter, N, P, K, organic carbon and
salinity. Only explicitly reported reference ranges can be manually retained.
Unknown methods/depths/dates remain null. A pH-specific header method is not assigned
to nutrient tests. No unit normalization or crop-specific interpretation occurs.

Multiple sample IDs, depth headers, duplicate parameter values, home-test strips
and recognized multicolumn sample headers return an ambiguous/manual-entry state.
Unreadable scans, absent Tesseract and parser failures have explicit unavailable
or manual-entry outputs. Complex tables, rotated scans, Burmese OCR and arbitrary
laboratory layouts require manual transcription. These limitations are not hidden
by fabricated values. The current parser is an MVP, not a validated general OCR service.

Confirmation rejects missing units/locators, nonfinite/negative values, pH outside
0–14, percentages over 100, future sample dates and ambiguous duplicate
parameter/depth/method tuples. It accepts one sample per confirmation, with
different depth/method measurements kept separately. The operator must still
check scientific plausibility and actual report provenance.

The current confirmation replaces the latest correction while preserving original
OCR; audit retains confirmation events, not a full history of every correction.
Deleting the source photo deletes its report records; confirm this retention
policy before production use. A sample result is never applied to an entire field
or used to overwrite SoilGrids. No real private lab report was supplied or tested.

Generate a labeled synthetic fixture:

```sh
python server/examples/make_synthetic_lab_report.py /tmp/synthetic-soil-report.png
```

On Windows pass `--font C:\\Windows\\Fonts\\arial.ttf` and a new private output path.
