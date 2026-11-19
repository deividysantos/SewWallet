-- CreateTable
CREATE TABLE "ReportFilter" (
    "id" TEXT NOT NULL,
    "userId" TEXT NOT NULL,
    "report" TEXT NOT NULL,
    "params" JSONB NOT NULL,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "ReportFilter_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "ReportFilter_userId_report_key" ON "ReportFilter"("userId", "report");

-- AddForeignKey
ALTER TABLE "ReportFilter" ADD CONSTRAINT "ReportFilter_userId_fkey" FOREIGN KEY ("userId") REFERENCES "User"("id") ON DELETE CASCADE ON UPDATE CASCADE;

